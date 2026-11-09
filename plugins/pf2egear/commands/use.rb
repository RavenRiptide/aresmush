module AresMUSH
  module Pf2egear
    class PF2UseItemCmd
      include CommandHandler

      attr_accessor :category, :item_num, :use_option

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.category = downcase_arg(args.arg1)
        second_parse = trimmed_list_arg(args.arg2, "/")
        self.item_num = second_parse ? integer_arg(second_parse[0]) : nil
        self.use_option = second_parse ? trim_arg(second_parse[1]) : nil

        @numcheck = trim_arg(second_parse[0]) if second_parse
      end

      def required_args
        [ self.category, self.item_num ]
      end

      # Whose things these are: the enactor's own. In an encounter, their copy there.
      def holder
        enactor
      end

      # What a consumable does beyond being used up. Outside a fight, nothing the game keeps count of.
      def consumed(_item); end

      def check_valid_category
        return nil if [ "weapons", "weapon", "armor", "magicitem", "consumable", "consumables" ].include?(self.category)
        return t('pf2egear.bad_category')
      end

      def check_is_number
        return nil if @numcheck.to_i.to_s == @numcheck
        return t('pf2egear.must_specify_by_number')
      end

      def handle
        # Start by finding the item to be used.

        found = Pf2egear::Inventory.item(holder, self.category, self.item_num)

        return if Pf2e::CharState.emit_error!(client, found)

        item = found.state

        if !item
          client.emit_failure t('pf2egear.not_found')
          return
        end

        held = Pf2e::Equipment.held_by(item)

        return client.emit_failure(t('pf2egear.item_in_encounter', :item => item.name, :id => held.id)) if held

        inert = Pf2e::BoundItems.inert_for(holder, item)

        return client.emit_failure(t('pf2e.bound_item_cannot_use', :item => item.name, :feat => inert)) if inert

        # A scroll or a wand casts the spell it holds, and a feather fan or a staff one of its own.
        return used_spell_item(item) if Pf2e::SpellItems.spell_item?(item) || Pf2e::WaveFan.fan?(item) || Pf2e::Staves.staff?(item)

        # Consumables get their own, much simpler, handling, and do not require a use entry.
        if self.category.match? "consumable"
          Pf2e::SystemPrefix.tell_room(enactor_room, t('pf2egear.item_use_ok', :name => enactor.name, :item => item.name), 'action')

          consumed(item)

          new_quantity = item.quantity - 1

          if new_quantity.zero?
            Pf2egear.destroy_item(item, client, enactor)
          else
            item.update(quantity: new_quantity)
          end

          return
        end

        # Is this a usable item?

        use = item.use

        if use.empty?
          client.emit_failure t('pf2egear.not_usable')
          return
        end

        # Armour and a weapon have to be worn; a magic item has to be invested. Inventory says
        # which, and a consumable needs neither.
        needs = Pf2egear::Inventory.use_needs(self.category)

        if needs
          unless item.send(needs)
            client.emit_failure t('pf2egear.cannot_use_now', :action => needs.to_s)
            return
          end
        end

        # Some items have more than one use. Expect a valid self.use_option if this is the case.

        uses = use.keys || []

        if uses.size > 1 && !self.use_option
          client.emit_failure t('pf2egear.needs_use_option', :options => uses.sort.join(", "))
          return
        end

        if self.use_option && !uses.include?(self.use_option)
          client.emit_failure t('pf2egear.bad_use', :options => uses.sort.join(", "))
          return
        end

        selected_use = self.use_option || uses.first

        details = use[selected_use]

        base_msg = t('pf2egear.item_use_ok', :name => enactor.name, :item => item.name)
        use_option_msg = t('pf2egear.use_option', :use => selected_use)

        Pf2e::SystemPrefix.tell_room(enactor_room, base_msg + "%b" + use_option_msg, 'action')

        # Now that the item has been used, can it be used again? If not, destroy it.

        if details['charges']
          charges = details['charges'] - 1

          if charges.zero?
            use.delete(selected_use)
          else
            details['charges'] = charges
            use[selected_use] = details
          end

          item.update(use: use)

          if use.empty?
            Pf2egear.destroy_item(item, client, enactor)
          end

        end

      end

      # Outside an encounter nothing is rolled: the room is told the spell is cast, and a scroll is used up.
      def used_spell_item(item)
        return used_fan(item) if Pf2e::WaveFan.fan?(item)
        return used_staff(item) if Pf2e::Staves.staff?(item)

        done = Pf2e::SpellItems.use_outside!(enactor, item)

        return if Pf2e::CharState.emit_error!(client, done)

        Pf2e::SystemPrefix.tell_room(enactor_room, t('pf2e.spell_item_cast_outside', :name => enactor.name, :item => done.state['item'],
                                                                                    :spell => done.state['spell'], :rank => done.state['rank']), 'action')
      end

      # `use magicitem=<n>[/<spell>]` on a feather fan, outside an encounter: the room is told which spell.
      def used_fan(item)
        words = cmd.args.to_s.partition('=').last.split('/').map(&:strip).drop(1).reject(&:empty?)
        done = Pf2e::WaveFan.use_outside!(enactor, item, words)

        return if Pf2e::CharState.emit_error!(client, done)

        Pf2e::SystemPrefix.tell_room(enactor_room, t('pf2e.wave_fan_outside', :name => enactor.name, :spell => done.state['spell'],
                                                                              :item => item.name), 'action')
      end

      # `use weapons=<n>[/<spell>]` on a staff they prepared today, outside an encounter: the room is told
      # which spell, and no charge is counted.
      def used_staff(item)
        words = cmd.args.to_s.partition('=').last.split('/').map(&:strip).drop(1).reject(&:empty?)
        done = Pf2e::Staves.use_outside!(enactor, item, words)

        return if Pf2e::CharState.emit_error!(client, done)

        Pf2e::SystemPrefix.tell_room(enactor_room, t('pf2e.staff_cast_outside', :name => enactor.name, :spell => done.state['name'],
                                                                                :item => item.name), 'action')
      end

    end
  end
end
