module AresMUSH
  module Pf2e

    class PF2AdvanceArchetypeCmd
        include CommandHandler

        attr_accessor :specialty

        def parse_args
            args = cmd.parse_args(ArgParser.arg1_equals_arg2)
            self.specialty = downcase_arg(args.arg2)
        end

        def required_args
            [ self.specialty ]
        end

        def handle
            to_assign = enactor.pf2_to_assign
            
            # Get the archetype that was auto-assigned from the dedication feat.
            archetype = to_assign['archetype']
            
            unless archetype
              client.emit_failure "No archetype has been assigned."
              return
            end
            
            unless to_assign['archetype_specialty']&.include?('open')
              client.emit_failure "You don't need to assign an archetype specialty."
              return
            end

            # Validate the specialty choice.
            valid_specialties = Global.read_config('pf2e_archetype_specialty', archetype)
            
            unless valid_specialties && valid_specialties.key?(self.specialty.capitalize)
              valid_list = valid_specialties&.keys&.sort&.join(", ") || "none"
              client.emit_failure t('pf2e.adv_invalid_archetype_specialty', :archetype => archetype, :options => valid_list)
              return
            end
            
            # Assign the specialty.
            to_assign['archetype_specialty'] = self.specialty.capitalize
            chosen_specialty = self.specialty.capitalize
            
            # Get the archetype info.
            archetype_info = enactor.pf2_archetypeinfo
            
            # Assign the archetype specialty to the slot matching the archetype slot.
            if archetype == archetype_info["archetype1"]
              archetype_info["archetype_specialty1"] = chosen_specialty
            elsif archetype == archetype_info["archetype2"]
              archetype_info["archetype_specialty2"] = chosen_specialty
            elsif archetype == archetype_info["archetype3"]
              archetype_info["archetype_specialty3"] = chosen_specialty
            elsif archetype == archetype_info["archetype4"]
              archetype_info["archetype_specialty4"] = chosen_specialty
            end
            
            # Reassign the hashes so they can be saved.
            enactor.pf2_archetypeinfo = archetype_info
            enactor.pf2_to_assign = to_assign
            enactor.save
            
            client.emit_success t('pf2e.adv_archetype_specialty_assigned', :specialty => self.specialty.capitalize)
        end

    end

  end
end
