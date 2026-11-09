module AresMUSH
  module Pf2e

    # `alchemy` - what an alchemist will make at their next preparations, and what their reagents allow:
    # as they stand in the encounter here, where they are in one.
    class PF2AlchemyViewCmd
      include CommandHandler

      attr_accessor :who

      def parse_args
        self.who = trim_arg(cmd.args)
      end

      def handle
        char = Pf2e.get_character(self.who, enactor)

        return client.emit_failure(t('pf2e.not_found')) unless char
        return client.emit_failure(t('pf2e.alchemy_not_alchemist')) unless Alchemy.alchemist?(char)

        encounter = Combatants.encounter_here(enactor)
        holder = (encounter && CombatantStates.of(encounter, char)) || char

        client.emit PF2AlchemyTemplate.new(holder, client).render
      end
    end

    # `alchemy/prepare <item>[/<how many>]` - says what to make of the day's reagents. `alchemy/clear
    # [<item>]` takes it back off the list. What is on the list is made at the next rest.
    class PF2AlchemyPrepareCmd
      include CommandHandler

      attr_accessor :name, :quantity

      def parse_args
        named, _, quantity = cmd.args.to_s.rpartition('/')
        named = cmd.args.to_s if named.strip.empty?

        self.name = named.strip
        self.quantity = quantity.to_i.positive? ? quantity.to_i : 1
      end

      def required_args
        [ self.name ]
      end

      def handle
        done = Alchemy.prepare!(enactor, self.name, self.quantity)

        return if CharState.emit_error!(client, done)

        client.emit_success t('pf2e.alchemy_planned', :list => done.state.map { |name, many| "#{many} #{name}" }.join(', '))
      end
    end

    class PF2AlchemyClearCmd
      include CommandHandler

      attr_accessor :name

      def parse_args
        self.name = trim_arg(cmd.args)
      end

      def handle
        Alchemy.clear!(enactor, self.name)

        client.emit_success t('pf2e.alchemy_cleared')
      end
    end

    # Quick Alchemy:
    #
    #   `encounter/alchemy <item>[, <item>]`  spends a versatile vial for each item, to hand until your next
    #                                         turn; two at once with Double Brew
    #   `encounter/alchemy/vial`              makes a Quick Vial, which spends nothing and lasts until the
    #                                         end of your turn
    class PF2EncounterAlchemyCmd
      include CommandHandler

      attr_accessor :names

      def parse_args
        self.names = cmd.args.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      def quick_vial?
        cmd.switch.to_s.casecmp?('alchemy/vial')
      end

      def check_names
        return nil if quick_vial? || self.names.any?
        return t('dispatcher.invalid_syntax', :cmd => 'encounter/alchemy')
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter

        standing = CombatantStates.of(encounter, enactor)

        return client.emit_failure(t('pf2e.encounter_gear_not_in')) unless standing

        made = quick_vial? ? Alchemy.quick_vial!(standing) : Alchemy.quick!(standing, self.names)

        return if CharState.emit_error!(client, made)

        message = if quick_vial?
                    t('pf2e.alchemy_quick_vial', :name => enactor.name, :item => made.state)
                  else
                    t('pf2e.alchemy_quick', :name => enactor.name, :item => made.state.join(' and '))
                  end

        Pf2e::Encounters::Announce.tell(PF2Encounter[encounter.id], message, :room => enactor_room, :story => true)
      end
    end
  end
end
