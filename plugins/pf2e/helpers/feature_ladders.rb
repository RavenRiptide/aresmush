module AresMUSH
  module Pf2e

    # Class features that are steps of one progression: Expert Spellcaster, Master Spellcaster,
    # Legendary Spellcaster. The main sheet names only the highest step held, since it implies the
    # ones before it; `sheet/features` still lists every step at the level it came.
    #
    # Read from the names, one row per naming pattern, because the class tables name every
    # progression one of these ways. A name matches only when the rest of it is identical, so Master
    # Strike (a rogue's) is not a step after Expert Strikes (a monk's).
    module FeatureLadders

      LADDERS = [
        { 'prefix' => %w(Expert Master Legendary) },
        { 'prefix' => %w(Minor Moderate Major Extreme) },
        { 'suffix' => %w(Expertise Mastery Legend) },
        # The bare name is the first step: Juggernaut, then Greater Juggernaut.
        { 'prefix' => [ nil, 'Greater' ] }
      ].freeze

      # The names a held list would show: every name no other held name is a later step of.
      def self.collapse(names)
        held = Array(names).map(&:to_s)

        held.reject { |name| later_steps(name).any? { |step| held.include?(step) } }
      end

      # Every name that would be a later step of this one, under any ladder.
      def self.later_steps(name)
        LADDERS.flat_map do |ladder|
          ladder['prefix'] ? prefixed(name, ladder['prefix']) : suffixed(name, ladder['suffix'])
        end
      end

      def self.prefixed(name, words)
        at, rest = step_of(words) do |word|
          if word.nil?
            name
          elsif name.start_with?("#{word} ")
            name.delete_prefix("#{word} ")
          end
        end
        return [] unless at

        words[(at + 1)..].map { |word| "#{word} #{rest}" }
      end

      def self.suffixed(name, words)
        at, rest = step_of(words) { |word| name.delete_suffix(" #{word}") if name.end_with?(" #{word}") }
        return [] unless at

        words[(at + 1)..].map { |word| "#{rest} #{word}" }
      end

      # The step this name is on, and the rest of the name: the latest word that matches, so a name
      # that starts with a ladder word isn't read as the bare first step as well.
      def self.step_of(words)
        words.each_with_index.reverse_each do |word, at|
          rest = yield(word)
          return [ at, rest ] if rest
        end

        nil
      end
    end
  end
end
