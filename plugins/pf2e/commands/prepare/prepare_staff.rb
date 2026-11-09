module AresMUSH
  module Pf2e

    # prepare/staff <staff>[/<rank> = <spell>]: prepares a staff they carry for the day, and may expend a
    # prepared spell on it for more charges. With nothing after the switch, it says what they prepared today.
    class PF2PrepareStaffCmd
      include CommandHandler

      attr_accessor :staff, :rank, :spell

      def parse_args
        left, _equals, right = cmd.args.to_s.partition('=')
        name, _slash, rank = left.strip.rpartition('/')

        if name.empty? || rank.strip !~ /\A\d+\z/
          name = left.strip
          rank = nil
        end

        self.staff = name.strip.empty? ? nil : name.strip
        self.rank = rank ? rank.strip.to_i : nil
        self.spell = right.strip.empty? ? nil : right.strip
      end

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
      end

      def check_spell_has_rank
        return t('pf2e.staff_expend_rank') if self.spell && !self.rank
        return t('pf2e.staff_expend_needs_spell') if self.rank && !self.spell
      end

      def handle
        return show if self.staff.blank?

        outcome = Staves.prepare!(enactor, self.staff, self.rank, self.spell)

        return if CharState.emit_error!(client, outcome)

        made = outcome.state
        spent = made['expended']

        if made['new'] && !spent && made['charges'].to_i.zero?
          client.emit_success t('pf2e.staff_prepared_makeshift', :staff => made['staff'])
        elsif made['new']
          client.emit_success t('pf2e.staff_prepared', :staff => made['staff'], :charges => made['charges'])
        end

        return unless spent

        client.emit_success t('pf2e.staff_expended', :staff => made['staff'], :spell => spent['spell'], :rank => spent['rank'],
                                                     :charges => made['charges'])
      end

      def show
        current = Staves.prepared(enactor)

        return client.emit_ooc(t('pf2e.staff_none_today')) unless current

        spent = Array(current['expended']).map { |row| "#{row['spell']} (#{SpellItems.ordinal(row['rank'].to_i)})" }

        client.emit_ooc t('pf2e.staff_today', :staff => current['pick'], :charges => current['charges'],
                                              :expended => spent.empty? ? t('pf2e.staff_nothing_expended') : spent.join(', '))
      end
    end

    # unprepare/staff: takes back today's staff, and the spells expended on it, while nothing has been cast
    # from it.
    class PF2UnprepareStaffCmd
      include CommandHandler

      def check_is_approved
        return t('pf2e.not_approved') unless enactor.is_approved?
      end

      def handle
        outcome = Staves.unprepare!(enactor)

        return if CharState.emit_error!(client, outcome)

        spells = outcome.state['spells']

        client.emit_success t('pf2e.staff_unprepared_ok', :staff => outcome.state['staff'],
                                                          :spells => spells.empty? ? t('pf2e.staff_nothing_expended') : spells.join(', '))
      end
    end
  end
end
