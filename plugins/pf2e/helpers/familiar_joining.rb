module AresMUSH
  module Pf2e
    module Familiar

      # A familiar coming into an encounter, and leaving it. It comes only when its player says it is
      # there, since a familiar may be left somewhere safe or simply be elsewhere when a fight starts.
      #
      # It is a creature record with its master's encounter state as `master`, and a row in the order that
      # names its master's row: it is targeted by its id or its name, and acts on its master's turn.
      module Joining

        # `row` is the master's row in the order.
        def self.check(encounter, char, row)
          return Err.new(:familiar_none, 'pf2e.familiar_none', 'char' => char.name) unless Familiar.main_source(char)
          return Err.new(:master_absent, 'pf2e.familiar_master_absent', 'char' => char.name) unless row && row['state']
          return Err.new(:not_approved, 'pf2e.familiar_encounter_unapproved', 'char' => char.name) unless Familiar.approved?(char)

          name = Familiar.approved_record(char)['name'].to_s
          held = Combatants.rows(encounter)

          if (here = held.find { |one| one['master'].to_s == row['id'].to_s })
            return Err.new(:already_here, 'pf2e.familiar_encounter_here', 'name' => here['name'])
          end

          clash = held.find { |one| one['name'].to_s.casecmp?(name) }
          return Err.new(:name_clash, 'pf2e.familiar_encounter_clash', 'name' => name, 'ref' => "##{clash['id']}") if clash

          Ok.new(:state => name)
        end

        # It takes its master's place in the order, though it has no turn there.
        def self.join!(encounter, char, row)
          check(encounter, char, row).and_then do |name|
            npc = Pf2eNpc.create(:encounter => encounter, :master => Pf2eCombatantState[row['state']], :name => name,
                                 :number => encounter.last_number.to_i + 1)
            joined = Combatants.join(encounter, name, row['init'].to_f, :holder => npc, :master => row['id'])

            Ok.new(:state => { 'npc' => npc, 'row' => joined })
              .with_message('pf2e.familiar_encounter_joined', 'name' => name, 'char' => char.name,
                            'ref' => "##{joined['id']}", 'encounter' => encounter.id)
          end
        end

        # It leaves, letting go of anyone it held, and is gone with whatever it was under.
        def self.leave!(encounter, char, row)
          here = row ? Combatants.minions_of(encounter, row['id']).first : nil
          return Err.new(:not_here, 'pf2e.familiar_encounter_absent', 'char' => char.name) unless here

          freed = Holding.let_go(encounter, here['name'])
          Combatants.leave(encounter, here['id'])
          Pf2eNpc[here['npc']]&.delete

          Ok.new(:state => { 'freed' => freed })
            .with_message('pf2e.familiar_encounter_left', 'name' => here['name'], 'char' => char.name, 'encounter' => encounter.id)
        end
      end
    end
  end
end
