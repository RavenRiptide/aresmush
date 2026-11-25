module AresMUSH
  module Pf2e

    # What companion/wear and companion/remove share: an item as `<category>=<number>` (or `/`), as `gear`
    # numbers it, after a character's name for staff.
    module CompanionGearCommand
      def parse_args
        parts = cmd.args.to_s.strip.gsub(/\s*[=\/]\s*/, '=').split('=')

        self.character = parts.size > 2 ? parts.shift.strip : nil
        self.category = parts[0].to_s.strip.downcase.presence
        self.index = parts[1].to_s.strip.presence
      end

      def required_args
        [ self.category, self.index ]
      end

      def check_is_number
        return nil if self.index.to_i.to_s == self.index
        return t('pf2egear.must_specify_by_number')
      end

      def check_permissions
        if self.character
          return nil if enactor.has_permission?('manage_sheet')
          return t('dispatcher.not_allowed')
        end

        return nil if enactor.is_approved? || enactor.is_admin?
        return t('dispatcher.not_allowed')
      end

      def subject
        @subject ||= self.character ? Pf2e.get_character(self.character, enactor) : enactor
      end
    end

    # companion/wear <item>: puts an item from their inventory on their animal companion, investing it if it
    # has the invested trait. Staff: companion/wear <character>=<item>, which allows an item without the
    # companion trait.
    class PF2CompanionWearCmd
      include CommandHandler
      include CompanionOutcome
      include CompanionGearCommand

      attr_accessor :character, :category, :index

      def handle
        return client.emit_failure(t('pf2e.not_found')) unless subject

        outcome = Companion::Gear.wear!(subject, self.category, self.index.to_i, :staff => !self.character.nil?)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        state = outcome.state

        if self.character
          client.emit_success t('pf2e.companion_gear_worn_staff', :name => state['name'], :char => subject.name, :item => state['shown'])
        elsif state['invested']
          client.emit_success t('pf2e.companion_gear_worn_invested', :name => state['name'], :item => state['shown'],
                                :count => state['count'], :max => Companion::Gear::INVEST_LIMIT)
        else
          client.emit_success t('pf2e.companion_gear_worn', :name => state['name'], :item => state['shown'])
        end
      end
    end

    # companion/remove <item>: takes an item off their animal companion and puts it back in their inventory.
    # Staff: companion/remove <character>=<item>.
    class PF2CompanionRemoveCmd
      include CommandHandler
      include CompanionOutcome
      include CompanionGearCommand

      attr_accessor :character, :category, :index

      def handle
        return client.emit_failure(t('pf2e.not_found')) unless subject

        outcome = Companion::Gear.remove!(subject, self.category, self.index.to_i, :staff => !self.character.nil?)
        return client.emit_failure(rendered(outcome)) if outcome.err?

        state = outcome.state
        key = self.character ? 'pf2e.companion_gear_removed_staff' : 'pf2e.companion_gear_removed'
        client.emit_success t(key, :mid => state['mid'], :char => subject.name, :item => state['shown'])
      end
    end
  end
end
