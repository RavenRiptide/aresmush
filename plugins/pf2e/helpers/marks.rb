module AresMUSH
  module Pf2e

    # A creature someone has marked with an effect they are under: an investigator's stratagem marks the
    # creature it was devised against. Foundry spells the mark `target:mark:<slug>` when the one who marked
    # it acts on that creature, and `origin:mark:<slug>` when that creature acts on them.
    module Marks

      # What `holder`'s marks say about `other`, a combatant, under `prefix`.
      def self.seen(holder, other, prefix)
        return [] unless holder && other

        ActiveEffects.on(holder).filter_map do |effect|
          mark = effect.mark || {}

          mark['label'] == other.label && mark['slug'] ? "#{prefix}:mark:#{mark['slug']}" : nil
        end.uniq
      end

      # The effect `holder` is under that marks `other`, by the mark's slug.
      def self.marking(holder, other, slug)
        return nil unless holder && other

        ActiveEffects.on(holder).find { |effect| (effect.mark || {}) == { 'label' => other.label, 'slug' => slug } }
      end
    end
  end
end
