module AresMUSH
  module Pf2e

    # Feats a feat hands over once their prerequisites are met: Raging Intimidation gives Intimidating Glare
    # and Scare to Death "as soon as you meet the prerequisites". The feat names them:
    #
    #   feats_when_eligible: [ Intimidating Glare, Scare to Death ]
    #
    # What decides eligibility (a skill rank, a level) only moves when a draft does, so the check runs where
    # a draft writes: after each feat chargen gives, and as a level-up commits, before `commit_level_up!`
    # records the level. A feat given there is part of that level and goes with it on a rollback.
    module EligibleFeats

      KEY = 'feats_when_eligible'.freeze

      # The feats owed and not yet held, by name.
      def self.owed(char)
        held = DraftSheet.of(char).feat_names

        Pf2e.held_feat_details(char).flat_map { |_name, details| Array(details[KEY]) }
          .map(&:to_s).uniq.reject { |name| held.include?(name.upcase) }
      end

      # Gives each owed feat whose prerequisites the character now meets. Returns rendered messages.
      def self.settle!(char, client)
        ready = owed(char).select do |name|
          details = Global.read_config('pf2e_feats', name)

          details.is_a?(Hash) && Pf2e.can_take_feat_details?(char, name, details, char.pf2_level, :choice_gate => false)
        end

        return [] if ready.empty?

        Pf2e.grant_feats(:char => char, :value => ready, :charclass => char.pf2_base_info['charclass'], :client => client)
      end
    end
  end
end
