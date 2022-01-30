module AresMUSH
  module Pf2e
    class PF2BoostUnsetCmd
      include CommandHandler

      attr_accessor :type, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.type = downcase_arg(args.arg1)
        self.value = titlecase_arg(args.arg2)
      end

      def check_chargen_or_advancement

        if enactor.chargen_locked && !enactor.advancing || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif enactor.chargen_stage.zero?
          return t('chargen.not_started')
        else
          return nil
        end

      end

      def handle
        ##### VALIDATION SECTION #####
        # Verify that there are things to be unassigned that this command handles.

        working_boost_list = enactor.pf2_boosts_working
        valid_boost_types = working_boost_list.keys

        if !(valid_boost_types.include?(self.type))
          client.emit_failure t('pf2e.bad_option', :element=>"boost type", :options=>valid_boost_types.join(", "))
          return
        end

        # Make sure they've committed their base info and their abilities are correctly created.
        char_abilities = enactor.abilities

        if !char_abilities || !enactor.pf2_baseinfo_locked
          client.emit_failure t('pf2e.lock_info_first')
          return
        end

        # Is the value given in the command valid?
        ability_options = char_abilities.map { |a| a.name }

        if !(ability_options.include?(self.value))
          client.emit_failure t('pf2e.bad_option', :element=>"abilities", :options=>ability_options.join(", "))
          return
        end

        # Is the value given in the command assigned to that boost type?

        type_list = working_boost_list[self.type]

        index = type_list.find_index(self.value)

        if !index
          client.emit_failure t('pf2e.boost_not_assigned', :value=>self.value)
          return
        end
        ##### VALIDATION SECTION END #####

        # Let's do it. Find the reference value.

        starting_value = enactor.pf2_boosts[self.type][index]

        # Replace the working array element with the new value.
        type_list[index] = starting_value

        working_boost_list[self.type] = type_list

        # Modify base score appropriately.
        Pf2eAbilities.update_base_score(enactor, self.value, -2)

        enactor.update(pf2_boosts_working: working_boost_list)

        client.emit_success t('pf2e.reset_ok', :element=>self.value)

      end

    end
  end
end