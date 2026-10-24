# `rake script[pf2e_neutral_sheets]`, once, when encounters start holding what happens to characters:
# anyone in a running encounter takes their damage, conditions and effects into it, and every character's
# own sheet is left neutral.
refused = AresMUSH::Pf2e::CombatantStates.neutralize_all!

refused.each { |name, why| puts "#{name}: not changed - #{why}" }
puts "Character sheets are neutral; running encounters hold their state."
