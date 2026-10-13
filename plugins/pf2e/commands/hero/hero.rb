module AresMUSH
  module Pf2e

    # What the `hero` commands share: the scene the enactor is in, and the telling of its room and log.
    module HeroCommand
      def scene
        @scene ||= HeroPoints.scene_of(enactor)
      end

      def check_in_scene
        scene ? nil : t('pf2e.hero_no_scene')
      end

      # The encounter they stand in here, and their state in it.
      def encounter
        Combatants.encounter_here(enactor)
      end

      def standing
        found = encounter

        found ? CombatantStates.of(found, enactor) : nil
      end

      def tell_scene(message)
        enactor_room.emit_ooc message
        Scenes.add_to_scene(scene, message, Game.master.system_character, false, true)
      end
    end

    # `hero` - the Hero Points you hold in the scene here, and what they do. Whoever runs the scene sees
    # the party's.
    class PF2HeroViewCmd
      include CommandHandler
      include HeroCommand

      def handle
        lines = [ t('pf2e.hero_held', :count => HeroPoints.held(scene, enactor), :most => HeroPoints.most) ]

        if HeroPoints.may_award?(scene, enactor)
          party = HeroPoints.party(scene).map { |char| "#{char.name} #{HeroPoints.held(scene, char)}" }
          lines = [ t('pf2e.hero_party', :list => party.empty? ? t('pf2e.hero_party_empty') : party.join(', ')) ]
        end

        client.emit_ooc (lines + [ t('pf2e.hero_uses', :cost => HeroPoints.rpp_cost) ]).join('%r')
      end
    end

    # `hero/award [<why>]` - whoever runs the scene gives the whole party a Hero Point.
    class PF2HeroAwardCmd
      include CommandHandler
      include HeroCommand

      attr_accessor :why

      def parse_args
        self.why = trim_arg(cmd.args)
      end

      def check_runs_it
        return nil unless scene

        HeroPoints.may_award?(scene, enactor) ? nil : t('pf2e.hero_not_runner')
      end

      def handle
        rows = HeroPoints.award!(scene)

        return client.emit_failure(t('pf2e.hero_party_empty')) if rows.empty?

        counts = rows.map { |name, before, after| before == after ? t('pf2e.hero_award_full', :name => name, :count => after) : "#{name} #{after}" }

        tell_scene t(self.why ? 'pf2e.hero_awarded_for' : 'pf2e.hero_awarded', :name => enactor.name, :why => self.why,
                                                                              :list => counts.join(', '))
      end
    end

    # `hero/reroll` and `hero/boost` - a Hero Point on your last check: roll it again and keep the second
    # roll, or add 10 to a roll that came up under 10.
    class PF2HeroFortuneCmd
      include CommandHandler
      include HeroCommand

      def handle
        mode = cmd.switch.to_s.downcase
        found = HeroFortune.last_check(enactor, encounter, scene)
        face = found.ok? ? HeroFortune.face_for(mode, found.state['row']) : found

        return if CharState.emit_error!(client, face)

        spent = HeroPoints.spend!(scene, enactor)

        return if CharState.emit_error!(client, spent)

        tell_scene t("pf2e.hero_spends_#{mode}", :name => enactor.name, :die => found.state['row']['faces'].first)
        made = HeroFortune.again(enactor, found.state, face.state)

        if made.err?
          HeroPoints.refund!(scene, enactor)
          tell_scene t('pf2e.hero_kept', :name => enactor.name)

          return CharState.emit_error!(client, made)
        end

        client.emit_ooc t('pf2e.hero_left', :count => spent.state)
      end
    end

    # `hero/survive` - every Hero Point you hold, and at least one, not to die.
    class PF2HeroSurviveCmd
      include CommandHandler
      include HeroCommand

      # Dying happens in an encounter, so it is someone standing in the one here who is saved.
      def handle
        holder = standing

        return client.emit_failure(t('pf2e.hero_not_dying')) unless holder

        saved = nil

        History.recording(encounter, "#{enactor.name}: #{cmd.raw}") { saved = HeroPoints.survive!(scene, enactor, holder) }

        return if CharState.emit_error!(client, saved)

        tell_scene t('pf2e.hero_survives', :name => enactor.name)
      end
    end

    # `hero/buy` - a Hero Point for RPP.
    class PF2HeroBuyCmd
      include CommandHandler
      include HeroCommand

      def handle
        bought = HeroPoints.buy!(scene, enactor)

        return if CharState.emit_error!(client, bought)

        tell_scene t('pf2e.hero_bought', :name => enactor.name, :cost => HeroPoints.rpp_cost, :count => bought.state)
      end
    end

    # `hero/give <name>` - one of your Hero Points to someone in the scene who has none.
    class PF2HeroGiveCmd
      include CommandHandler
      include HeroCommand

      attr_accessor :name

      def parse_args
        self.name = trim_arg(cmd.args)
      end

      def required_args
        [ self.name ]
      end

      def handle
        to = Character.find_one_by_name(self.name)

        return client.emit_failure(t('pf2e.char_not_found')) unless to

        given = HeroPoints.give!(scene, enactor, to)

        return if CharState.emit_error!(client, given)

        tell_scene t('pf2e.hero_given', :name => enactor.name, :to => to.name)
      end
    end
  end
end
