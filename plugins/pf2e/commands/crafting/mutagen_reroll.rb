module AresMUSH
  module Pf2e

    # `encounter/mutagenreroll` - a Mutagenist's Field Discovery: end the mutagen affecting you to reroll
    # your last check, which must be a Fortitude save. A fortune effect, so it can't change a check already
    # rolled twice or one a Hero Point rerolled. It goes the way `hero/reroll` does: the change is made
    # again with your die rolled anew, then the mutagen ends.
    class PF2MutagenRerollCmd
      include CommandHandler

      FORTITUDE = 'save:fortitude'.freeze

      # Where the check was made: the scene here, and the encounter in it, as `hero/reroll` finds them.
      # Its own, because this file loads before the Hero Point commands.
      def scene
        @scene ||= HeroPoints.scene_of(enactor)
      end

      def check_in_scene
        scene ? nil : t('pf2e.hero_no_scene')
      end

      def encounter
        Combatants.encounter_here(enactor)
      end

      def standing
        found = encounter

        found ? CombatantStates.of(found, enactor) : nil
      end

      def tell_scene(message)
        SystemPrefix.emit(enactor_room, message, 'system', :ooc => true)
        SystemPrefix.log(scene, message, 'system', :ooc => true)
      end

      def holder
        standing || enactor
      end

      def handle
        unless ResearchField.ability?(holder, 'Mutagenist', ResearchField::FIELD_DISCOVERY)
          return client.emit_failure(t('pf2e.mutagen_reroll_not_mutagenist'))
        end

        mutagen = Mutagens.on(holder).max_by { |one| one.id.to_i }

        return client.emit_failure(t('pf2e.mutagen_reroll_none')) unless mutagen

        found = HeroFortune.last_check(enactor, encounter, scene)

        return if CharState.emit_error!(client, found)
        return client.emit_failure(t('pf2e.mutagen_reroll_not_fortitude')) unless found.state['row']['about'] == FORTITUDE

        name = mutagen.name
        tell_scene t('pf2e.mutagen_reroll_spends', :name => enactor.name, :mutagen => ActiveEffects.bare_name(mutagen),
                                                   :die => found.state['row']['faces'].first)

        made = HeroFortune.again(enactor, found.state, nil)

        return CharState.emit_error!(client, made) if made.err?

        # The change made again put the mutagen back as it stood; it ends now.
        now = holder
        ended = Mutagens.on(now).select { |one| one.name == name }.max_by { |one| one.id.to_i }

        ActiveEffects.remove(now, ended) if ended
      end
    end
  end
end
