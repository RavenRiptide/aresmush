module AresMUSH
  module Pf2e

    # Uncommon and rare spells a character may learn, which staff unlock once the player has spent RPP on
    # one through a request. An unlock is permission to learn the spell by the character's usual means: a
    # level-up pick, a gated or innate pick, or Learn a Spell into a spellbook. It doesn't teach the spell.
    #
    # An unlock is a `spell_unlock` grant, which no rollback reaches. Staff can only unlock spells for an
    # approved character, because chargen records its sheet only for a character with no grants yet.
    module SpellUnlocks

      def self.unlocked(char)
        Array(Ledger.derived(char)['spell_unlocks'])
      end

      def self.unlocked?(char, spell)
        unlocked(char).any? { |one| one.to_s.casecmp?(spell.to_s) }
      end

      # A spell's rarity, from its traits.
      def self.common?(details)
        ItemAccess.common?(details)
      end

      def self.unlock!(char, spell, by:)
        # An approved character who predates the ledger has no grants, so their current sheet becomes the
        # imported transaction this lands on, or the refold after it would empty their sheet.
        Ledger.seed_from_sheet!(char)

        Ledger.write(char, :source_type => 'staff', :source_ref => "spell unlock: #{spell}", :granted_by => by) do |txn|
          txn.grant('spell_unlock', 'spell' => spell)
        end
      end

      def self.relock!(char, spell, by:)
        Ledger.revert_matching!(char, 'spell_unlock', { 'spell' => spell }, :by => by)
      end
    end
  end
end
