module AresMUSH
  module Pf2e
    # Playtest only: a player awards themselves XP. `selfaward/xp <amount>`, or `selfaward/xp me=<amount>`
    # as it has always been typed. Staff award anyone with award/xp.
    class PF2SelfAwardXPCmd
      include CommandHandler

      attr_accessor :target, :award

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_optional_arg2)

        if args.arg2
          self.target = trim_arg(args.arg1)
          self.award = integer_arg(args.arg2)
        else
          self.award = integer_arg(args.arg1)
        end
      end

      def required_args
        [ self.award ]
      end

      def check_playtest
        return nil if Pf2e.playtest?
        return t('pf2e.playtest_only')
      end

      def check_self
        return nil if !self.target || self.target.downcase == 'me' || self.target.downcase == enactor.name.downcase
        return t('pf2e.playtest_self_only')
      end

      def check_valid_award
        return nil unless self.award.zero?
        return t('pf2e.bad_value', :item => 'XP award')
      end

      def handle
        Pf2e.award_xp(enactor, self.award, enactor.name, 'Playtest self-award')

        client.emit_success t('pf2e.xp_awarded', :awardee => enactor.name, :award => self.award)
      end

    end
  end
end
