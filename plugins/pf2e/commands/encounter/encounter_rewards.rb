module AresMUSH
  module Pf2e

    # `+e/level <n>` - the GM sets the party's level for the encounter's difficulty; `+e/level 0` goes back
    # to the characters' average.
    class PF2EncounterLevelCmd
      include CommandHandler

      attr_accessor :level

      def parse_args
        self.level = integer_arg(cmd.args)
      end

      def required_args
        [ self.level ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        encounter.update(:party_level => self.level.positive? ? self.level : nil)

        client.emit_success Difficulty.shown(PF2Encounter[encounter.id])
      end
    end

    # `+e/award [<encounter id>]` - what PF2e recommends for an encounter, and what has been paid.
    # `+e/award [<encounter id>=]<character>=<xp>/<amount> <coin>` - staff pay a character for it.
    class PF2EncounterAwardCmd
      include CommandHandler

      attr_accessor :encounter_id, :who, :xp, :money

      def parse_args
        parts = cmd.args.to_s.split('=').map(&:strip)
        self.encounter_id = parts.shift.delete_prefix('#') if parts.size == 3 || (parts.size == 1 && parts.first.match?(/\A#?\d+\z/))
        self.who, pay = parts

        return unless pay

        xp, money = pay.split('/', 2).map(&:strip)
        amount, coin = money.to_s.split

        self.xp = xp.to_i
        self.money = money ? Pf2egear.convert_money(amount.to_i, (coin || 'gp').downcase) : 0
      end

      def check_staff
        return nil if enactor.is_admin? || enactor.has_permission?('award_xp')

        t('dispatcher.not_allowed')
      end

      def handle
        encounter = self.encounter_id ? PF2Encounter[self.encounter_id] : Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.bad_id', :type => 'encounter')) unless encounter

        return client.emit(Difficulty.recommended(encounter)) unless self.who
        return client.emit_failure(t('dispatcher.invalid_syntax', :cmd => 'e/award')) unless self.xp

        pay(encounter)
      end

      def pay(encounter)
        char = Character.named(self.who)

        return client.emit_failure(t('pf2e.not_found')) unless char

        reason = t('pf2e.award_reason', :id => encounter.id)

        Pf2e.award_xp(char, self.xp, enactor.name, reason) unless self.xp.zero?
        Pf2egear.pay_player(char, self.money, enactor.name, reason) unless self.money.zero?

        held = (encounter.awarded || {})[char.name] || {}
        encounter.update(:awarded => (encounter.awarded || {}).merge(
          char.name => { 'xp' => held['xp'].to_i + self.xp, 'money' => held['money'].to_i + self.money }))

        client.emit_success t('pf2e.award_paid', :name => char.name, :xp => self.xp,
                                                 :money => Pf2egear.display_money(self.money).strip, :id => encounter.id)
      end
    end
  end
end
