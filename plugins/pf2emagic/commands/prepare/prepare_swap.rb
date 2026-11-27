module AresMUSH
  module Pf2emagic
    # Ten minutes spent changing a prepared spell after daily preparations (PreparedSwaps):
    #
    #   prepare/swap <spell> [<rank>] = <new spell>     a prepared spell replaced at the same rank
    #   prepare/reprepare <spell> [= <new spell>]       a spell cast today prepared again
    class PF2PrepareSwapCmd
      include CommandHandler

      attr_accessor :spell, :rank, :new_spell

      def parse_args
        if cmd.args.to_s.include?("=")
          args = cmd.parse_args(ArgParser.arg1_equals_arg2)
          left = trim_arg(args.arg1).to_s
          self.new_spell = titlecase_arg(args.arg2)
        else
          left = trim_arg(cmd.args).to_s
        end

        # A rank may follow the spell: prepare/swap Fireball 5 = Haste.
        matched = left.match(/\A(.*\S)\s+(\d+)\z/)
        self.rank = matched ? matched[2] : nil
        self.spell = titlecase_arg(matched ? matched[1] : left)
      end

      def required_args
        swap? ? [ self.spell, self.new_spell ] : [ self.spell ]
      end

      def swap?
        cmd.switch.to_s.casecmp?('swap')
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
      end

      def handle
        unless enactor.magic
          client.emit_failure t('pf2emagic.not_caster')
          return
        end

        outcome = if swap?
                    PreparedSwaps.swap(enactor, self.spell, self.new_spell, self.rank)
                  else
                    PreparedSwaps.reprepare(enactor, self.spell, self.new_spell)
                  end

        return if Pf2e::CharState.emit_error!(client, outcome)

        made = outcome.state

        if swap?
          client.emit_success t('pf2emagic.swap_ok', :from => made['from'], :to => made['to'], :rank => made['rank'],
                                :source => made['source'])
        elsif made['from'] == made['to']
          client.emit_success t('pf2emagic.reprepare_ok', :spell => made['from'], :rank => made['rank'])
        else
          client.emit_success t('pf2emagic.reprepare_new_ok', :from => made['from'], :to => made['to'], :rank => made['rank'])
        end
      end
    end
  end
end
