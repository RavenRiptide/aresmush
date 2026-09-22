module AresMUSH
  module Pf2egear

    # The gear commands in an encounter, on what a character carries there: the encounter's copy of their
    # gear, taken as they entered it (`Pf2e::Equipment`). Outside, the same commands work on their own.
    # Held here rather than in commands/ because each extends a command defined there, which loads first.
    module EncounterGear
      def holder
        return @holder if defined?(@holder)

        encounter = Pf2e::Combatants.encounter_here(enactor)
        @holder = encounter ? Pf2e::CombatantStates.of(encounter, enactor) : nil
      end

      def check_in_encounter
        holder ? nil : t('pf2e.encounter_gear_not_in')
      end
    end

    # `+e/use <category>=<number>[/<use>]`
    class PF2EncounterUseCmd < PF2UseItemCmd
      include EncounterGear
    end

    # `+e/equip <category>=<number>` - draw a weapon, put on armour, strap on a shield.
    class PF2EncounterEquipCmd < PF2GearEquipCmd
      include EncounterGear
    end

    # `+e/unequip <category>=<number>` - stow it again.
    class PF2EncounterUnequipCmd < PF2GearUnequipCmd
      include EncounterGear
    end

    # `+e/gear [<combatant>]` - what a character carries in the encounter here.
    class PF2EncounterGearCmd
      include CommandHandler

      attr_accessor :who

      def parse_args
        self.who = trim_arg(cmd.args)
      end

      def handle
        encounter = Pf2e::Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter

        found = Pf2e::Combatants.find(encounter, self.who || enactor.name)

        return if Pf2e::CharState.emit_error!(client, found)
        return client.emit_failure(t('pf2e.encounter_sheet_creature', :ref => found.state.ref)) if found.state.creature?

        char = Pf2e::Actors.of(found.state.holder).person
        allowed = Pf2e::Sheet.viewable?(enactor, char, 'combat')

        return if Pf2e::CharState.emit_error!(client, allowed)

        client.emit Pf2eDisplayGearTemplate.new(found.state.holder, client).render
      end
    end

    # `+e/loot <combatant>=<category> <item>[/<quantity>]` - gives someone an item in the encounter here,
    # from the catalogue, at no cost. Staff, and the trusted GMs an admin gives `trusted_gm` to; an
    # encounter's own GM does not give things out. What it gives becomes theirs when the encounter ends.
    class PF2EncounterLootCmd
      include CommandHandler

      attr_accessor :who, :category, :item_name, :quantity

      def parse_args
        who, _, what = cmd.args.to_s.partition('=')
        named, _, quantity = what.strip.rpartition('/')
        named = what.strip if named.empty?

        self.who = who.strip
        self.category, _, item_name = named.strip.partition(' ')
        self.category = Pf2egear::Inventory.canonical(self.category.downcase).to_s
        self.item_name = item_name.strip.downcase
        self.quantity = quantity.to_i.positive? ? quantity.to_i : 1
      end

      def required_args
        [ self.who, self.item_name ]
      end

      def check_may_give
        return nil if enactor.is_admin?
        return t('pf2e.loot_not_trusted') unless enactor.has_permission?('trusted_gm')

        nil
      end

      def check_valid_category
        return nil if Pf2egear::Inventory.categories.include?(self.category)

        t('pf2egear.bad_category')
      end

      def handle
        encounter = Pf2e::Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless enactor.is_admin? || Pf2e::Combatants.gm?(enactor, encounter)

        found = Pf2e::Combatants.find(encounter, self.who)

        return if Pf2e::CharState.emit_error!(client, found)
        return client.emit_failure(t('pf2e.encounter_sheet_creature', :ref => found.state.ref)) if found.state.creature?

        name, info = catalogue_entry

        return client.emit_failure(t('pf2egear.not_found')) unless name

        many = Pf2egear::Inventory.stackable?(self.category) ? self.quantity : 1
        Pf2egear.create_item(found.state.holder, self.category, name, many, info)

        message = t('pf2e.loot_given', :name => enactor.name, :item => name, :many => many, :who => found.state.label)

        client.emit_success message
        enactor_room.emit_ooc message
      end

      # The item by name, exactly or as the only one holding the words typed.
      def catalogue_entry
        list = Global.read_config(Pf2egear::Inventory.config(self.category)) || {}
        exact = list.find { |named, _info| named.downcase == self.item_name }

        return exact if exact

        found = list.select { |named, _info| named.downcase.include?(self.item_name) }

        found.size == 1 ? found.first : nil
      end
    end

    [ PF2EncounterUseCmd, PF2EncounterEquipCmd, PF2EncounterUnequipCmd,
      PF2EncounterLootCmd ].each { |command| command.prepend(Pf2e::Recorded) }
  end
end
