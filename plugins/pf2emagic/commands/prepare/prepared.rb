module AresMUSH
  module Pf2emagic
    class PF2DisplayPreparedCmd
      include CommandHandler

      attr_accessor :caster_class

      def parse_args
        self.caster_class = titlecase_arg(cmd.args)
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
        return nil
      end

      # Their prepared spells, then the day's choices their feats have them make (Ancestral Longevity's
      # skill), which a character with no spells may still have. Naming a caster class shows its spells only.
      def handle
        daily = self.caster_class ? [] : Pf2e::DailyChoices.listing(enactor)
        failure = spells

        client.emit_failure(failure) if failure && (daily.empty? || failure != t('pf2emagic.you_cast_no_spells'))
        client.emit BorderedListTemplate.new(daily, t('pf2e.daily_title')).render unless daily.empty?
      end

      # Shows their prepared spells, or returns why there are none to show.
      def spells
        magic = enactor.magic

        return t('pf2emagic.you_cast_no_spells') unless magic && Pf2emagic.is_caster?(enactor)

        # A class whose only preparations are through a feat (Split Slot, Spell Mastery) is listed too.
        prepared_spells = magic.spells_prepared.dup
        ((magic.slot_pairs || {}).keys + (magic.mastered_spells || {}).keys).each { |cc| prepared_spells[cc] ||= {} }

        if prepared_spells.empty?
          prepares = (magic.tradition || {}).keys.any? { |cc| Pf2emagic.get_caster_type(cc) == 'prepared' }
          return t(prepares ? 'pf2emagic.no_prepared_spells' : 'pf2emagic.prepares_nothing')
        end

        if self.caster_class
          class_spells = prepared_spells[self.caster_class] || {}

          return t('pf2emagic.no_prepared_spells_class', :cc => self.caster_class) if
            class_spells.empty? && !prepared_spells.key?(self.caster_class)

          # Keep the { class => { rank => spells } } shape the template expects.
          prepared_spells = { self.caster_class => class_spells }
        end

        client.emit PF2DisplayPreparedSpellsTemplate.new(enactor, prepared_spells, client).render

        nil
      end

    end
  end
end
