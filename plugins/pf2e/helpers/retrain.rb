module AresMUSH
  module Pf2e

    # Swapping a feat a character holds for another, as PF2e's retraining rules allow: "you generally can't
    # make choices you couldn't make when you selected the original option." The replacement goes in the
    # same slot, so it is the same type of feat, no higher than the slot's level, and must meet its
    # prerequisites as the character stood at that level.
    #
    # A feat may forbid it with `no_retrain:` - `into` (nobody may retrain into it), `out` (nobody may
    # retrain out of it) or `both`.
    #
    # The retrain is written at the slot's level: a `level_up` grant for a slot a level-up gave, so rolling
    # that level back puts the old feat back, and a `staff` one for a chargen slot, which no rollback reaches.
    module Retrain

      NO_RETRAIN = %w{into out both}.freeze

      # A replacement whose own grants or choices a retrain would have to open. A retrain records one feat
      # for another; those need the feat-gaining path a level-up has.
      OPENS = %w{grants feat_choice level_choices at_level magic_stats init_magic daily_choice}.freeze

      def self.forbids?(details, direction)
        flag = details.is_a?(Hash) ? details['no_retrain'].to_s.downcase : ''

        flag == 'both' || flag == direction.to_s
      end

      # The pure half: may `old` (as `taking` says it is held) be retrained into `new`?
      # taking: { 'feat' =>, 'bucket' =>, 'level' => }. Returns an Err, or nil when allowed.
      def self.check(taking, old_details, new_name, new_details)
        old = taking['feat'].to_s

        return Err.new(:retrain_same, 'pf2e.retrain_same', 'feat' => old) if new_name.to_s.casecmp?(old)
        return Err.new(:retrain_out_forbidden, 'pf2e.retrain_out_forbidden', 'feat' => old) if forbids?(old_details, 'out')
        return Err.new(:retrain_into_forbidden, 'pf2e.retrain_into_forbidden', 'feat' => new_name) if forbids?(new_details, 'into')

        bucket = taking['bucket'].to_s
        types = Array((new_details || {})['feat_type']).map { |t| t.to_s.downcase }

        # A dedication starts an archetype, which a retrained slot can't.
        return Err.new(:retrain_dedication, 'pf2e.retrain_dedication', 'feat' => new_name) if types.include?('dedication')

        unless types.include?(bucket)
          return Err.new(:retrain_bad_type, 'pf2e.retrain_bad_type', 'feat' => new_name, 'type' => bucket.gsub('charclass', 'class'))
        end

        wanted = ((new_details || {})['prereq'] || {})['level'].to_i
        slot = taking['level'].to_i

        if wanted > slot
          return Err.new(:retrain_too_high, 'pf2e.retrain_too_high', 'feat' => new_name, 'wanted' => wanted, 'slot' => slot)
        end

        nil
      end

      # Whether a replacement only needs recording: no grants, choices or casting of its own.
      def self.opens_anything?(details)
        OPENS.any? { |key| details.is_a?(Hash) && !details[key].blank? }
      end

      # What a feat being retrained away hands over that a retrain can take back with it: the feats its
      # `grants: feat:` gave. Anything else it granted cannot be traced back to it, so a feat granting
      # more is refused.
      def self.reversible?(details)
        return true unless details.is_a?(Hash)

        grants = details['grants']
        others = OPENS - [ 'grants' ]

        return false if others.any? { |key| !details[key].blank? }
        return true if grants.blank?

        grants.is_a?(Hash) && (grants.keys - [ 'feat' ]).empty?
      end

      def self.granted_feats(details)
        Array(((details || {})['grants'] || {})['feat'])
          .map { |entry| entry.is_a?(Hash) ? entry['name'] : entry }
          .compact.map(&:to_s)
      end

      # How the character holds a feat: the bucket and level of its newest live taking, or nil.
      def self.taking(char, feat)
        row = Ledger.explain_for(char, :kind => 'grant_feat', :key => feat).first

        return nil unless row

        payload = row['payload'] || {}
        level = row['effective_level'].to_i

        { 'feat' => payload['feat'].to_s, 'bucket' => payload['bucket'].to_s, 'level' => level < 1 ? 1 : level }
      end

      # The feats they hold that would stop meeting their prerequisites without `feat`: one naming it under
      # `feat`, or under `orfeat` with none of the others held.
      def self.dependents(char, feat)
        held = Pf2e.held_feat_details(char)
        names = held.map { |name, _| name.to_s.upcase }

        held.filter_map do |name, details|
          prereq = details['prereq'] || {}
          needs = Array(prereq['feat']).map { |f| f.to_s.upcase }
          either = Array(prereq['orfeat']).map { |f| f.to_s.upcase }
          wanted = feat.to_s.upcase

          next name if needs.include?(wanted)
          next name if either.include?(wanted) && (either - [ wanted ]).none? { |f| names.include?(f) }

          nil
        end
      end

      # ----------------------------------------------------------------------------------------------
      # A retrain a level owes (`advance/retrain`, `advance/info retrain`)
      #
      # Both commands ask the same questions, so `advance/info retrain` never lists a feat `advance/retrain`
      # then refuses.
      # ----------------------------------------------------------------------------------------------

      # The first retrain their open level owes and hasn't filled: { 'feat', 'from', 'bucket', 'level', … },
      # or nil.
      def self.owed(char)
        Array((char.pf2_advancement || {})['retrains']).find { |one| one['to'].blank? }
      end

      # Feats they hold that need the old feat stop every replacement, so this is asked once, not per feat.
      def self.dependents_block(char, owed)
        needing = dependents(char, owed['from'])
        return nil if needing.empty?

        t('pf2e.retrain_dependents', :feat => owed['from'], :feats => needing.sort.join(', '))
      end

      # The questions about one replacement that read the character, as a rendered message or nil:
      # a second familiar, a repeat the feat doesn't allow, and whether they could take it at all - its
      # class or ancestry and its prerequisites, through the same `can_take_feat_details?` the feat lists
      # use, measured at the old feat's slot level as PF2e's retraining rules say. `taken` is the times they
      # hold it, when the caller has a tally. `explain: false` skips the costly explanation of a refusal, for
      # a list that only needs yes or no.
      def self.candidate_block(char, owed, new_name, new_details, taken: nil, explain: true)
        return Familiar.block_message(char) if Familiar.blocks?(char, new_details)

        repeat = Pf2e.feat_repeat_block(char, new_name, new_details, taken, owed['level'])
        return repeat if repeat

        return nil if Pf2e.can_take_feat_details?(char, new_name, new_details, owed['level'].to_i)
        return t('pf2e.does_not_qualify') unless explain

        Pf2e.explain_feat_block(char, new_details) || t('pf2e.does_not_qualify')
      end

      # Everything `advance/retrain` asks of the character about one replacement.
      def self.sheet_block(char, owed, new_name, new_details)
        dependents_block(char, owed) || candidate_block(char, owed, new_name, new_details)
      end

      # The feats `owed` may be retrained into, sorted: every feat passing `check` and `candidate_block`.
      # Feats depending on the old one aren't asked here; `dependents_block` stops the retrain outright.
      def self.options(char, owed)
        found = Pf2e.get_feat_details(owed['from'])
        old_details = found.is_a?(Array) ? found[1] : {}
        type = owed['bucket'].to_s.downcase
        slot = owed['level'].to_i
        tally = Pf2e.feat_tally(char)
        list = []

        Pf2e::SheetReads.holding(char) do
          (Global.read_config('pf2e_feats') || {}).each_pair do |name, details|
            next unless details.is_a?(Hash)

            # Cheap filters first, so most candidates never reach the sheet.
            next unless Array(details['feat_type']).any? { |one| one.to_s.downcase == type }
            next if ((details['prereq'] || {})['level']).to_i > slot
            next if check(owed, old_details, name, details)
            next if candidate_block(char, owed, name, details, :taken => tally[name.to_s.upcase], :explain => false)

            list << name
          end
        end

        list.sort
      end

      # Records the retrain: the old taking and the feats it granted are revoked, and the replacement is
      # granted in its slot. Returns the transaction id.
      def self.retrain!(char, taking, old_details, new_name, by:)
        level = taking['level'].to_i
        marker = Ledger.level_revocation_marker(level, 'retrain')

        Ledger.revert_matching!(char, 'grant_feat', { 'feat' => taking['feat'], 'bucket' => taking['bucket'] },
                                :by => marker, :materialize => false, :limit => 1)

        granted_feats(old_details).each do |granted|
          Ledger.revert_matching!(char, 'grant_feat', { 'feat' => granted }, :by => marker, :materialize => false, :limit => 1)
        end

        source = level > 1 ? 'level_up' : 'staff'

        Ledger.write(char, :source_type => source, :source_ref => "retrain #{taking['feat']} into #{new_name}",
                     :effective_level => level, :granted_by => by) do |txn|
          txn.grant('grant_feat', 'bucket' => taking['bucket'], 'feat' => new_name)
        end
      end
    end
  end
end
