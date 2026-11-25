module AresMUSH
  module Pf2e

    # `encounter/sheet/companion [<character, or the companion's #id or name>]` - an animal companion's sheet as
    # it stands in this encounter. Every sheet is open, so anyone may see anyone's.
    class PF2EncounterCompanionSheetCmd
      include CommandHandler

      attr_accessor :target

      def parse_args
        self.target = trim_arg(cmd.args)
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter

        char, row = whose(encounter)
        return unless char
        return client.emit_failure(t('pf2e.companion_none', :char => char.name)) unless Companion.main(char)
        return client.emit_failure(t('pf2e.companion_sheet_not_here', :char => char.name)) unless row

        view = Companion::SheetView.build(char, :npc => Pf2eNpc[row['npc']])

        client.emit PF2FamiliarSheetTemplate.new(view, client).render
      end

      # The master, and their companion's row here if it has joined.
      def whose(encounter)
        rows = Combatants.rows(encounter)
        char = self.target ? named(encounter, rows) : enactor
        return nil unless char

        master = rows.find { |row| row['char'].to_s == char.id.to_s }
        [ char, master ? Combatants.minions_of(encounter, master['id'], 'companion').first : nil ]
      end

      # A companion here by its id or name, a character here, or any character by name.
      def named(encounter, rows)
        found = Combatants.find(encounter, self.target)

        if found.ok?
          combatant = found.state

          if combatant.minion? && Actors.of(combatant.holder).minion_kind == 'companion'
            master = rows.find { |row| row['id'].to_i == combatant.master.to_i }
            return master ? Character[master['char']] : nil
          end

          return combatant.holder.character if combatant.holder && !combatant.creature?

          client.emit_failure t('pf2e.companion_sheet_not_companion', :target => combatant.label)
          return nil
        end

        char = Pf2e.get_character(self.target, enactor)
        client.emit_failure t('pf2e.not_found') unless char
        char
      end
    end
  end
end
