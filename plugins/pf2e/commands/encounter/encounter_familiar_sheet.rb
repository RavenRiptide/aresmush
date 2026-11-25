module AresMUSH
  module Pf2e

    # `encounter/sheet/familiar [<character, or the familiar's #id or name>]` - a familiar's sheet as it
    # stands in this encounter. Every sheet is open, so anyone may see anyone's.
    class PF2EncounterFamiliarSheetCmd
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
        return client.emit_failure(t('pf2e.familiar_none', :char => char.name)) unless Familiar.main_source(char)
        return client.emit_failure(t('pf2e.familiar_sheet_not_here', :char => char.name)) unless row

        view = Familiar::SheetView.build(char, :familiar => Pf2eNpc[row['npc']])

        client.emit PF2FamiliarSheetTemplate.new(view, client).render
      end

      # The master, and their familiar's row here if it has joined.
      def whose(encounter)
        rows = Combatants.rows(encounter)
        char = self.target ? named(encounter, rows) : enactor
        return nil unless char

        master = rows.find { |row| row['char'].to_s == char.id.to_s }
        [ char, master ? Combatants.minions_of(encounter, master['id'], 'familiar').first : nil ]
      end

      # A familiar here by its id or name, a character here, or any character by name.
      def named(encounter, rows)
        found = Combatants.find(encounter, self.target)

        if found.ok?
          combatant = found.state

          if combatant.minion? && Actors.of(combatant.holder).minion_kind == 'familiar'
            master = rows.find { |row| row['id'].to_i == combatant.master.to_i }
            return master ? Character[master['char']] : nil
          end

          return combatant.holder.character if combatant.holder && !combatant.creature?

          client.emit_failure t('pf2e.familiar_sheet_not_familiar', :target => combatant.label)
          return nil
        end

        char = Pf2e.get_character(self.target, enactor)
        client.emit_failure t('pf2e.not_found') unless char
        char
      end
    end
  end
end
