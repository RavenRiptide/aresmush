module AresMUSH
  module Pf2e
    module Companion

      # A companion's death, and replacing it. Three cases, each a different amount of change:
      #
      #   raised or reincarnated   staff mark it dead, then alive again: its status only
      #   a new animal, same build `companion/replace`: a new name for staff to approve; the ledger is untouched
      #   a different companion    `companion/replace <type>`: a new name, a new type, and nimble or savage and
      #                            each specialization chosen again; on approval each old choice is rewritten
      #                            at the level it was made
      #
      # Until staff approve a replacement, the old companion stays in force. A replacement is kept on the
      # companion's record as `replacement`: { 'type' (a type label, nil for the same build), 'choices'
      # (feat => labels), 'from' (the old name) }. Staff approving it writes a `companion_replaced` record,
      # which sheet/history shows.
      #
      # Only an approved character may replace a companion (in chargen, cg/option and cg/undo change it), and
      # not mid-level: rewriting history while a level is open would collide with the level's draft.

      INCREDIBLE_OPTIONS = %w{Nimble Savage}.freeze

      def self.dead?(char, companion = main(char))
        entry(char, companion)['status'] == 'dead'
      end

      def self.replacement(char, companion = main(char))
        found = entry(char, companion)['replacement']
        found.is_a?(Hash) ? found : nil
      end

      # Staff mark it dead, or alive again. Returns an Err, or Ok.
      def self.mark_dead!(char, dead:)
        companion = main(char)
        return Err.new(:companion_none, 'pf2e.companion_none', 'char' => char.name) unless companion
        return Err.new(:companion_already_dead, 'pf2e.companion_already_dead', 'char' => char.name) if dead && dead?(char, companion)
        return Err.new(:companion_not_dead, 'pf2e.companion_not_dead', 'char' => char.name) if !dead && !dead?(char, companion)

        held = entry(char, companion)
        dead ? held['status'] = 'dead' : held.delete('status')
        save_entry!(char, companion, held)

        Ok.new(:state => held)
      end

      # Why they can't start replacing their companion, as a locale key, or nil.
      def self.replace_refusal(char)
        companion = main(char)

        return 'pf2e.companion_none_yours' unless companion
        return 'pf2e.companion_replace_chargen' unless char.is_approved?
        return 'pf2e.companion_replace_advancing' if char.advancing
        return 'pf2e.companion_replace_untyped' unless companion['type']
        return 'pf2e.companion_replace_busy' if replacement(char, companion)

        nil
      end

      # The feats whose choices a new type makes again, with how many each made: [ [ feat, count ] ].
      def self.choices_to_remake(char, companion = main(char))
        labels = labels_reader(char, :draft => false)

        held(char, :draft => false).select { |_name, details| %w{incredible specialized}.include?(details['companion_stage'].to_s) }
                                   .map { |name, _details| [ name, labels.call(name).size ] }
                                   .reject { |_name, count| count.zero? }
      end

      # Starts replacing it, with a new animal of the same build (`type` nil) or of the type label given.
      # The type is checked first. Returns an Err, or Ok with the request opened.
      def self.start_replacement!(char, type = nil)
        companion = main(char)
        chosen = nil

        unless type.blank?
          offered = type_options(char, companion['source'])
          chosen = offered.find { |label| label.casecmp?(type.to_s.strip) }

          unless chosen
            return Err.new(:companion_replace_bad_type, 'pf2e.companion_replace_bad_type', 'type' => type.to_s.strip,
                           'feat' => companion['source'], 'options' => offered.join(', '))
          end
        end

        held = entry(char, companion)
        old = name_of(char, companion)
        held['replacement'] = { 'type' => chosen, 'choices' => {}, 'from' => old }
        held.delete('pending')
        save_entry!(char, companion, held)

        found = job(char, companion) || open_request!(char)
        Jobs.comment(found, char, t('pf2e.companion_replace_comment', :old => old, :type => replacement_type(char).downcase), false) if found

        Ok.new(:state => { 'request' => found, 'old' => old, 'type' => replacement_type(char) })
      end

      # The type the replacement will be: its own, or the companion's for the same build.
      def self.replacement_type(char, companion = main(char))
        found = replacement(char, companion)
        type = found && found['type'] ? split_label(found['type']).first : companion['type']
        type.to_s
      end

      # The replacement as Stats.of takes it.
      def self.replacement_companion(char, companion = main(char))
        found = replacement(char, companion)
        return companion unless found && found['type']

        type, size = split_label(found['type'])
        by_stage = ->(stage) { choices_to_remake(char, companion).map(&:first).select { |feat| Global.read_config('pf2e_feats', feat, 'companion_stage') == stage } }
        path = by_stage.call('incredible').flat_map { |feat| Array(found['choices'][feat]) }.first
        specializations = by_stage.call('specialized').flat_map { |feat| Array(found['choices'][feat]) }.map do |label|
          named, choice = split_label(label)
          { 'name' => named, 'choice' => named == 'Auspice' ? servitors(char) : choice }
        end

        companion.merge('type' => type, 'size' => size, 'path' => path.to_s.downcase.presence, 'specializations' => specializations)
      end

      # The choices still to make for a new type: [ feat, ... ], a feat named once per choice left.
      def self.choices_left(char, companion = main(char))
        found = replacement(char, companion)
        return [] unless found && found['type']

        choices_to_remake(char, companion).flat_map do |feat, count|
          [ feat ] * [ count - Array(found['choices'][feat]).size, 0 ].max
        end
      end

      # What a feat's choice may be for the replacement.
      def self.replacement_options(char, feat, companion = main(char))
        stage = Global.read_config('pf2e_feats', feat.to_s, 'companion_stage').to_s
        return INCREDIBLE_OPTIONS if stage == 'incredible'

        proposed = replacement_companion(char, companion)
        found = Stats.of(proposed, :level => char.pf2_level, :grants => merged_grants(held(char, :draft => false)))
        return [] unless found

        specialization_labels(Stats.catalogue, :held => proposed['specializations'].map { |one| one['name'] },
                                               :speeds => found['speeds'].keys, :feat => feat, :servitors => servitors(char))
      end

      # Makes one of the replacement's choices. Returns an Err, or Ok.
      def self.choose_for_replacement!(char, feat, choice)
        companion = main(char)
        found = replacement(char, companion)
        return Err.new(:companion_replace_none, 'pf2e.companion_replace_none') unless found

        remake = choices_to_remake(char, companion)

        # The same build keeps every choice, and so does a new type for a companion that never advanced.
        if !found['type'] || remake.empty?
          return Err.new(:companion_replace_same_build, 'pf2e.companion_replace_same_build', 'old' => found['from'])
        end

        named = remake.map(&:first).find { |one| one.casecmp?(feat.to_s.strip) }

        unless named
          return Err.new(:companion_replace_not_needed, 'pf2e.companion_replace_not_needed', 'feat' => feat.to_s.strip,
                         'feats' => remake.map(&:first).join(', '))
        end

        return Err.new(:companion_replace_full, 'pf2e.companion_replace_full', 'feat' => named) unless choices_left(char, companion).include?(named)

        offered = replacement_options(char, named, companion)
        picked = offered.find { |label| label.casecmp?(choice.to_s.strip) }

        unless picked
          return Err.new(:companion_replace_bad_choice, 'pf2e.companion_replace_bad_choice', 'choice' => choice.to_s.strip,
                         'feat' => named, 'options' => offered.join(', '))
        end

        held = entry(char, companion)
        (held['replacement']['choices'][named] ||= []) << picked
        save_entry!(char, companion, held)

        request = job(char, companion)
        Jobs.comment(request, char, t('pf2e.companion_replace_option_comment', :feat => named, :choice => picked), false) if request

        Ok.new(:state => { 'feat' => named, 'choice' => picked, 'left' => choices_left(char, companion) })
      end

      # Withdraws a replacement still waiting, putting the old name back in force. Returns an Err, or Ok.
      def self.cancel_replacement!(char)
        companion = main(char)
        found = replacement(char, companion)
        return Err.new(:companion_replace_none, 'pf2e.companion_replace_none') unless found

        request = job(char, companion)
        held = entry(char, companion)
        held.delete('replacement')
        held.delete('pending')
        held.delete('job')
        save_entry!(char, companion, held)

        Jobs.close_job(char, request, t('pf2e.companion_replace_cancel_comment')) if request

        Ok.new(:state => { 'old' => found['from'] })
      end

      # What a replacement still needs before staff can approve it, as words: its name, and each choice left.
      def self.replacement_missing(char, companion = main(char))
        out = []
        out << t('pf2e.companion_field_name') if entry(char, companion).dig('pending', 'name').blank?
        out.concat(choices_left(char, companion).uniq)
        out
      end

      # The rewrite a new type needs: [ { 'choice', 'from', 'to', 'level' } ] for each recorded choice of the
      # companion feat and of the feats whose choices were made again, each at the level it was made. A choice
      # that comes out the same is left alone.
      def self.rewrite_plan(recorded, source, replacement)
        return [] unless replacement && replacement['type']

        rows = recorded.map { |name, label, level| { 'choice' => name, 'from' => label, 'level' => level.to_i } }
        plan = rows.select { |row| row['choice'].casecmp?(source) }.map { |row| row.merge('to' => replacement['type']) }

        (replacement['choices'] || {}).each do |feat, labels|
          made = rows.select { |row| row['choice'].casecmp?(feat) }.sort_by { |row| row['level'] }
          made.zip(Array(labels)).each { |row, label| plan << row.merge('to' => label) if label }
        end

        plan.reject { |row| row['from'] == row['to'] }
      end

      # Carries out an approved replacement's rewrite and records it. Each level's choices go in a transaction
      # of their own, as a level-up's would (staff at level 1, which no rollback reaches), and each old choice
      # is revoked under its level's marker, so a rollback of that level treats the new choice as that level's.
      def self.apply_replacement!(char, companion, by:)
        found = replacement(char, companion)
        Ledger.seed_from_sheet!(char)

        rewrite_plan(Pf2e.recorded_choices(char), companion['source'], found).group_by { |row| row['level'] }.sort.each do |level, rows|
          rows.each do |row|
            Ledger.revert_matching!(char, 'make_choice', { 'choice' => row['choice'], 'label' => row['from'] },
                                    :by => Ledger.level_revocation_marker(level, 'companion'), :materialize => false, :limit => 1)
          end

          Ledger.write(char, :source_type => level > 1 ? 'level_up' : 'staff', :source_ref => "companion replaced at level #{level}",
                       :effective_level => [ level, 1 ].max, :granted_by => by.name) do |txn|
            rows.each { |row| txn.grant('make_choice', 'choice' => row['choice'], 'label' => row['to']) }
          end
        end

        Ledger.write(char, :source_type => 'companion', :source_ref => 'companion replaced', :effective_level => char.pf2_level,
                     :granted_by => by.name) do |txn|
          txn.grant('companion_replaced', 'old_name' => found['from'], 'old_type' => companion['type'],
                                          'new_name' => entry(char, companion).dig('pending', 'name'),
                                          'new_type' => replacement_type(char, companion))
        end
      end
    end
  end
end
