module AresMUSH
  module Pf2e

    # An ability a creature cannot use again for a while: a breath it "can't use again for 1d4 rounds".
    # The rounds are rolled as it is used and the GM alone is told when it is back; using it before then
    # is the GM's to allow, and they are told that too.
    module Recharge

      KEY = 'recharge'.freeze

      # The sentence that says so, and what it calls the ability, which a passive one leaves out:
      #
      #   can't use Flame Breath again for 1d4 rounds
      #   can't use this ability again for 1d4 rounds
      #   can't use Captivating Pollen for 1d4 rounds
      #   can't be used again for 1d4 rounds
      WAIT = /can['’]t (?:use (?<what>[^.;%]{1,80}?)|be used)(?<again> again)? for (?<rounds>\d*d\d+|\d+) rounds?/i

      # The wait an ability's own words give it. One that says `again` is about the ability it is written
      # in, whatever it calls it; one that does not has to name it, since "can't use reactions for 1 round"
      # is what the ability does to someone else.
      def self.wait(name, own)
        own['text'].to_s.to_enum(:scan, WAIT).map { Regexp.last_match }.find do |found|
          found[:again] || found[:what].to_s.downcase.include?(name.to_s.downcase)
        end
      end

      def self.rounds_of(name, own)
        found = wait(name, own)

        found ? found[:rounds] : nil
      end

      # Which of a creature's abilities wait when this one is used: itself, and any other its words name
      # beside it - a linnorm "can't use Corrosive Breath or Double Breath again".
      def self.waiting(name, own, abilities)
        said = wait(name, own)&.[](:what).to_s.gsub(/#{Regexp.escape(name)}/i, '')
        beside = Array(abilities).map { |one| one['name'].to_s }
                                 .select { |other| !other.empty? && said.match?(/\b#{Regexp.escape(other)}\b/i) }

        [ name ] + beside
      end

      def self.ready(holder)
        TurnState.of(holder)[KEY] || {}
      end

      # The ability has been used: a warning where it was not back, and the round it will be.
      def self.used(scene, name, own, out)
        rounds = rounds_of(name, own)

        return unless rounds && scene.encounter

        holder = scene.actor.holder
        now = scene.encounter.round.to_i
        back = ready(holder)[name].to_i

        out['gm'] << Telling.event('pf2e.recharge_not_back', :actor => scene.actor.label, :action => name, :round => back) if back > now

        rolled = Pf2e.roll_formula(rounds)
        gone = waiting(name, own, Actors.of(holder).own_abilities).to_h { |one| [ one, now + rolled + 1 ] }
        TurnState.write(holder, KEY => ready(holder).merge(gone))
        out['gm'] << Telling.event('pf2e.recharge_set', :actor => scene.actor.label, :action => name, :rounds => rolled,
                                                       :round => now + rolled + 1)
      end

      # A critical hit brings back what the creature's own words say it does: Draconic Momentum.
      MOMENTUM = /recharges? (?:their|its|his|her) (.+?) whenever (?:they|it|he|she) scores? a critical hit/i

      def self.critical_hit(scene, out)
        holder = scene.actor.holder

        return unless Actors.of(holder).creature?

        Array(holder.stat_block['actions']).filter_map { |one| one['text'].to_s[MOMENTUM, 1] }.each do |named|
          waiting = ready(holder).keys.find { |name| name.casecmp?(named) }

          next unless waiting

          TurnState.write(holder, KEY => ready(holder).except(waiting))
          out['gm'] << Telling.event('pf2e.recharge_back', :actor => scene.actor.label, :action => waiting)
        end
      end
    end
  end
end
