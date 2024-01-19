module AresMUSH
  module Pf2emagic
    class PF2DisplaySpellCmd
      include CommandHandler

      attr_accessor :search_term

      def parse_args

        self.search_term = downcase_arg(cmd.args)

      end

      def required_args

        [ self.search_term ]

      end

      def handle

        spell_list = Global.read_config('pf2e_spells').keys

        spells = spell_list.select {|spell| spell.downcase.match? self.search_term }

        client.emit spell_list

        client.emit spells

        if spells.size > 1
          template = PF2DisplayManySpellTemplate.new(spells, client)
        elsif spells.empty?
          client.emit_failure t('pf2emagic.no_match', :item => "spells")
          return
        else
          template = PF2DisplayOneSpellTemplate.new(spells.first, client)
        end

        client.emit template.render
      end

    end
  end
end
