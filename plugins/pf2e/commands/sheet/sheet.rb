module AresMUSH
  module Pf2e

    class PF2DisplaySheetCmd
      include CommandHandler

      attr_accessor :section, :target, :levels

      # `sheet/history` also takes levels: `sheet/history 5`, `sheet/history 3-7`, or
      # `sheet/history <name>=3-7`. A name can't be digits, so a bare number is a level.
      def parse_args
        self.section = cmd.switch ? downcase_arg(cmd.switch) : "all"
        self.target = trim_arg(cmd.args)

        return unless self.section == 'history' && self.target

        if self.target.include?('=')
          self.target, self.levels = self.target.split('=', 2).map(&:strip)
          self.target = nil if self.target.empty?
        elsif self.target =~ /\A[\d\s-]+\z/
          self.levels = self.target
          self.target = nil
        end
      end

      def handle
        range = nil

        if self.levels
          range = Pf2e::LevelHistory.parse_range(self.levels)
          return client.emit_failure(t('pf2e.sheet_history_bad_range', :range => self.levels)) unless range
        end

        char = Pf2e.get_character(self.target, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

        # Whether the section exists at all is Pf2e::Sheet's business. Every sheet is open, so who
        # is asking does not matter.
        outcome = Pf2e::Sheet.available(char, self.section)

        return if Pf2e::CharState.emit_error!(client, outcome)

        template = Pf2eSheetTemplate.new(char, outcome.state, client, char.pf2_base_info, char.pf2_faith)
        template.history_range = range

        # A figure asks which feats, items and conditions carry effects, and a sheet shows a great
        # many figures. Rendering inside a read block asks once.
        rendered = Pf2e::SheetReads.holding(char) { template.render }

        client.emit rendered
      end

    end

  end
end
