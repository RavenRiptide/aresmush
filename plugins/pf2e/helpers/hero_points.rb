module AresMUSH
  module Pf2e

    # Hero Points.
    #
    # They are a scene's: each player character in a scene starts it with one, may hold three, and takes
    # none to the next. Whoever runs the scene holds none, and awards one to the whole party at a time.
    # A player spends one to roll a check again or to add 10 to one that rolled low (`HeroFortune`), all
    # they hold to stop dying, or 3 RPP to buy one; and may give one to someone who has none.
    #
    # The count is kept for the scene by character id (`Pf2eHeroPool`). Someone not written there yet
    # holds what a scene starts them with, so nobody has to be dealt in.
    module HeroPoints

      def self.settings
        Global.read_config('pf2e', 'hero_points') || {}
      end

      def self.start
        (settings['start'] || 1).to_i
      end

      def self.most
        (settings['most'] || 3).to_i
      end

      def self.rpp_cost
        (settings['rpp_cost'] || 3).to_i
      end

      # The scene a character is in, which is the one in their room.
      def self.scene_of(char)
        char.room&.scene
      end

      # The character behind whoever is asked about: themselves, or whose state in an encounter this is.
      def self.character(holder)
        Actors.of(holder).person
      end

      # The scene someone in an encounter is in: the encounter's, which holds whether or not they are in
      # its room.
      def self.scene_for(holder)
        Gm.encounter_of(holder)&.scene || scene_of(character(holder))
      end

      # What to tell someone who is dying or has died and holds a Hero Point: that it would save them.
      # Nothing for a creature, or for someone with none.
      def self.dying_hint(holder)
        return nil if Actors.of(holder).creature? || !dying?(holder)

        scene = scene_for(holder)
        count = scene ? held(scene, character(holder)) : 0

        count.positive? ? { 'name' => holder.name, 'count' => count } : nil
      end

      # What a sheet says of them: what they hold in the scene they are in, or that they are in none.
      def self.shown(holder)
        char = character(holder)
        scene = scene_for(holder)

        scene ? t('pf2e.hero_sheet', :count => held(scene, char), :most => most) : t('pf2e.hero_sheet_no_scene')
      end

      # Who runs a scene: whoever runs an encounter in it, and in a scene with none, whoever owns it.
      def self.runners(scene)
        running = scene.encounters.to_a.map { |encounter| PF2Encounter.gm_of(encounter) }.compact

        (running.empty? ? [ scene.owner ] : running).compact.uniq(&:id)
      end

      def self.runner?(scene, char)
        runners(scene).any? { |one| one.id == char.id }
      end

      def self.may_award?(scene, char)
        runner?(scene, char) || char.is_admin?
      end

      # The player characters of a scene: whoever has posed in it, is in an encounter in it, or is in
      # its room now, but for who runs it.
      def self.party(scene)
        fighting = scene.encounters.to_a.flat_map { |encounter| encounter.states.to_a.map(&:character) }
        present = scene.room ? Rooms.online_chars_in_room(scene.room) : []

        (scene.participants.to_a + fighting + present).compact.uniq(&:id).reject { |char| runner?(scene, char) }
                                                      .sort_by(&:name)
      end

      def self.counts(scene)
        Pf2eHeroPool.find(:scene_id => scene.id).first&.counts || {}
      end

      def self.held(scene, char)
        kept = counts(scene)[char.id.to_s]

        return kept.to_i if kept

        runner?(scene, char) ? 0 : start
      end

      # Counts by character id, written over the scene's.
      def self.write!(scene, changed)
        pool = Pf2eHeroPool.find(:scene_id => scene.id).first || Pf2eHeroPool.create(:scene => scene)

        pool.update(:counts => (pool.counts || {}).merge(changed.transform_keys(&:to_s)))
      end

      # One more for each of the party, up to the most anyone holds. Answers each as
      # `[ name, before, after ]`.
      def self.award!(scene)
        rows = party(scene).map { |char| [ char, held(scene, char), [ held(scene, char) + 1, most ].min ] }

        write!(scene, rows.to_h { |char, _before, after| [ char.id, after ] })

        rows.map { |char, before, after| [ char.name, before, after ] }
      end

      # Spends so many, or all they hold where `count` is `:all`. Answers what is left.
      def self.spend!(scene, char, count = 1)
        have = held(scene, char)
        count = have if count == :all

        return Err.new(:no_hero_points, 'pf2e.hero_none') if have < 1 || have < count

        write!(scene, char.id => have - count)

        Ok.new(:state => have - count)
      end

      # The Hero Points spent in a change, by name, given back as it is taken back, or spent again as it
      # is put back. Answers each as `"Aria 2"`: who, and what they hold now.
      def self.moved!(scene, spent, back)
        rows = (spent || {}).filter_map do |name, count|
          char = Character.find_one_by_name(name)

          char ? [ char, (held(scene, char) + (back ? count.to_i : -count.to_i)).clamp(0, most) ] : nil
        end

        write!(scene, rows.to_h { |char, now| [ char.id, now ] }) if rows.any?

        rows.map { |char, now| "#{char.name} #{now}" }
      end

      # One back, for a spend that came to nothing.
      def self.refund!(scene, char)
        write!(scene, char.id => [ held(scene, char) + 1, most ].min)
      end

      # A Hero Point for RPP: refused at the most they may hold, and by the RPP ledger where they have
      # not the RPP.
      def self.buy!(scene, char)
        have = held(scene, char)

        return Err.new(:hero_at_most, 'pf2e.hero_at_most', 'most' => most) if have >= most

        refused = Player.spend_rpp(char, rpp_cost, 'Hero Point')

        return Err.new(:no_rpp, 'pf2e.hero_rpp_refused', 'why' => refused) if refused

        write!(scene, char.id => have + 1)

        Ok.new(:state => have + 1)
      end

      # One of theirs to someone in the party who has none.
      def self.give!(scene, from, to)
        return Err.new(:no_hero_points, 'pf2e.hero_none') if held(scene, from) < 1
        return Err.new(:hero_not_party, 'pf2e.hero_not_party', 'name' => to.name) if
          to.id == from.id || party(scene).none? { |one| one.id == to.id }
        return Err.new(:hero_has_some, 'pf2e.hero_has_some', 'name' => to.name) if held(scene, to).positive?

        write!(scene, from.id => held(scene, from) - 1, to.id => 1)

        Ok.new(:state => held(scene, from))
      end

      def self.dying?(holder)
        Pf2e.condition_level(holder, 'Dying').positive? || (holder.pf2_is_dead ? true : false)
      end

      # Someone dying, or dead in the encounter they stand in, spends every Hero Point they hold - at
      # least one - not to die: no longer dying, unconscious with no Hit Points, and no more wounded
      # than they were. Answers how many it cost.
      def self.survive!(scene, char, holder)
        return Err.new(:hero_not_dying, 'pf2e.hero_not_dying') unless dying?(holder)

        cost = held(scene, char)
        spent = spend!(scene, char, :all)

        return spent if spent.err?

        holder.update(:pf2_is_dead => false) if holder.pf2_is_dead
        Pf2e.remove_condition(holder, 'Dying', true)
        Pf2e.set_condition(holder, 'Unconscious', nil, 'granted_by' => Pf2eHP::NO_HIT_POINTS)

        Ok.new(:state => cost)
      end
    end
  end
end
