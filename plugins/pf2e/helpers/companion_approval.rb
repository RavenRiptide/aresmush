module AresMUSH
  module Pf2e
    module Companion

      # A companion's name, and staff approving it. Each companion keeps, under its id in `pf2_companions`:
      #
      #   pending    { 'name' } a name waiting for staff
      #   approved   { 'name', 'source', 'type', 'by', 'at' } what staff approved, for that source and type
      #   job        the open approval request's id
      #
      # Approval belongs to the companion's source and type, so a different type (a replacement) waits for
      # staff again. A rename waits under `pending` while the approved name stays in force. In chargen, staff
      # approve the companion with the application; after it, a request opens.

      def self.record(char)
        held = char.pf2_companions
        held.is_a?(Hash) ? Marshal.load(Marshal.dump(held)) : {}
      end

      def self.main(char)
        list(char).first
      end

      def self.entry(char, companion)
        return {} unless companion

        ((record(char)['companions'] || {})[companion['id']] || {}).dup
      end

      def self.save_entry!(char, companion, entry)
        held = record(char)
        held['companions'] ||= {}
        held['companions'][companion['id']] = entry
        char.update(:pf2_companions => held)
      end

      def self.approved_record(char, companion = main(char))
        approved = entry(char, companion)['approved']
        return nil unless companion && approved.is_a?(Hash)

        same = approved['source'].to_s == companion['source'].to_s && approved['type'].to_s == companion['type'].to_s
        same ? approved : nil
      end

      def self.approved?(char, companion = main(char))
        !approved_record(char, companion).nil?
      end

      # They have a companion staff haven't approved as it is. It can't join an encounter until they do.
      def self.awaiting_approval?(char)
        companion = main(char)
        !companion.nil? && !approved?(char, companion)
      end

      # The name as the player sees it: a rename waiting, else the approved name.
      def self.name_of(char, companion = main(char))
        held = entry(char, companion)
        ((held['pending'] || held['approved'] || {})['name']).presence
      end

      # Who a sentence is about: its name, or "Your animal companion" before it has one.
      def self.subject(char, companion = main(char))
        name_of(char, companion) || t('pf2e.companion_subject_unnamed')
      end

      # What approval still needs, as `companion_field_*` keys.
      def self.missing(char, companion = main(char))
        return [] unless companion

        out = []
        out << 'type' unless companion['type']
        out << 'name' unless name_of(char, companion)
        out
      end

      # A companion with no name yet, which cg/review asks them to name.
      def self.unfinished_name?(char)
        companion = main(char)
        !companion.nil? && name_of(char, companion).nil?
      end

      def self.missing_named(char, companion = main(char))
        missing(char, companion).map { |key| t("pf2e.companion_field_#{key}") }.join(', ')
      end

      def self.job(char, companion = main(char))
        id = entry(char, companion)['job']
        found = id.blank? ? nil : Job[id]

        found && found.is_open? ? found : nil
      end

      def self.request_category
        found = Global.read_config('pf2e', 'companion_job_category')
        found.blank? ? Jobs.request_category : found
      end

      # Sets its name, already checked (Names.name). Returns the request it was written to, if one is open
      # or opened. In chargen there is no request: staff approve it with the application.
      def self.set_name!(char, name)
        companion = main(char)
        held = entry(char, companion)
        held['pending'] = { 'name' => name }
        save_entry!(char, companion, held)

        return nil unless char.is_approved?

        found = job(char, companion) || open_request!(char)
        Jobs.comment(found, char, t('pf2e.companion_name_comment', :name => name), false) if found
        found
      end

      def self.summary(char, companion)
        none = t('pf2e.companion_detail_unset')
        found = replacement(char, companion)

        unless found
          return t('pf2e.companion_request_body', :char => char.name, :source => companion['source'],
                   :type => companion['type'] || none, :name => name_of(char, companion) || none)
        end

        stage = Stats.stage_name(companion)
        old = t(dead?(char, companion) ? 'pf2e.companion_request_old_dead' : 'pf2e.companion_request_old',
                :name => found['from'], :stage => stage, :type => companion['type'].to_s.downcase)
        new_name = entry(char, companion).dig('pending', 'name') || none
        choices = (found['choices'] || {}).flat_map { |feat, labels| Array(labels).map { |label| "#{feat}: #{label}" } }

        t('pf2e.companion_request_body_replace', :char => char.name, :old => old,
          :new => t('pf2e.companion_request_new', :name => new_name, :type => replacement_type(char, companion).downcase),
          :choices => choices.empty? ? t('pf2e.companion_request_no_choices') : choices.join(', '))
      end

      # Opens the request staff approve the companion in, if none is open. Returns it, or nil when the jobs
      # plugin refused.
      def self.open_request!(char)
        companion = main(char)
        return nil unless companion

        found = job(char, companion)
        return found if found

        made = Jobs.create_job(request_category, t('pf2e.companion_request_title', :char => char.name), summary(char, companion), char)
        return nil unless made[:job]

        held = entry(char, companion)
        held['job'] = made[:job].id
        save_entry!(char, companion, held)

        made[:job]
      end

      # After a level: a companion waiting for approval gets a request. Returns what to tell the player, or
      # nil. Unlike a familiar, a companion waiting doesn't stop their next level.
      def self.after_level!(char)
        return nil unless awaiting_approval?(char)

        fresh = job(char).nil?
        found = open_request!(char)
        return nil unless found && fresh

        companion = main(char)
        key = name_of(char, companion) ? 'pf2e.companion_request_opened' : 'pf2e.companion_request_opened_unnamed'
        t(key, :source => companion['source'], :number => found.id)
      end

      # Staff approve its name as it stands, or the replacement waiting. `by` is the staff character, or nil
      # for the chargen approval.
      def self.approve!(char, by:, close: true)
        companion = main(char)
        return Err.new(:companion_none, 'pf2e.companion_none', 'char' => char.name) unless companion

        approver = by || Game.master.system_character

        if replacement(char, companion)
          return Err.new(:companion_replace_approve_advancing, 'pf2e.companion_replace_approve_advancing', 'char' => char.name) if char.advancing

          left = replacement_missing(char, companion)
          unless left.empty?
            return Err.new(:companion_replace_incomplete, 'pf2e.companion_replace_incomplete', 'char' => char.name, 'missing' => left.join(', '))
          end

          open = job(char, companion)
          proposed = replacement_companion(char, companion)
          proposed_stats = Stats.of(proposed, :level => char.pf2_level, :grants => merged_grants(held(char, :draft => false)))
          coming_off = Gear.coming_off(char, companion, :type => proposed['type'], :size => proposed_stats && proposed_stats['size'])

          apply_replacement!(char, companion, :by => approver)
          char = Character[char.id]
          Gear.settle!(char)
          companion = main(char)

          held = entry(char, companion)
          held['approved'] = { 'name' => held.dig('pending', 'name'), 'source' => companion['source'], 'type' => companion['type'],
                               'by' => approver.name, 'at' => Time.now.to_i }
          # A new animal: the old one's picture goes with it.
          %w{pending replacement status job image}.each { |key| held.delete(key) }
          save_entry!(char, companion, held)

          came_off = coming_off.map { |item| t('pf2e.companion_gear_came_off', :name => held['approved']['name'], :item => item) }
          comment = ([ t('pf2e.companion_approved_comment', :name => held['approved']['name']) ] + came_off).join(' ')
          Jobs.close_job(approver, open, comment) if open && close

          return Ok.new(:state => held.merge('replaced' => true, 'came_off' => coming_off))
        end

        unless missing(char, companion).empty?
          return Err.new(:companion_details_missing, 'pf2e.companion_details_missing', 'char' => char.name,
                         'missing' => missing_named(char, companion))
        end

        open = job(char, companion)
        held = entry(char, companion)
        held['approved'] = { 'name' => name_of(char, companion), 'source' => companion['source'], 'type' => companion['type'],
                             'by' => approver.name, 'at' => Time.now.to_i }
        held.delete('pending')
        held.delete('job')
        save_entry!(char, companion, held)

        Jobs.close_job(approver, open, t('pf2e.companion_approved_comment', :name => held['approved']['name'])) if open && close

        Ok.new(:state => held)
      end

      # Staff send its name back with a reason, in the request, which stays open.
      def self.reject!(char, by:, reason:)
        return Err.new(:companion_none, 'pf2e.companion_none', 'char' => char.name) unless main(char)

        found = job(char) || open_request!(char)
        return Err.new(:companion_no_request, 'pf2e.companion_no_request', 'char' => char.name) unless found

        Jobs.comment(found, by, t('pf2e.companion_rejected_comment', :reason => reason), false)

        Ok.new(:state => entry(char, main(char)))
      end

      # Chargen approval approves the companion with the application. One approved without a name or type is
      # finished in a request.
      def self.approve_with_app!(char)
        return unless main(char)

        open_request!(char) if approve!(char, :by => nil, :close => false).err?
      end

      # The companion check in `app`, laid out as the sheet check is. Nil without a companion.
      def self.app_review(char)
        companion = main(char)
        return nil unless companion

        status = if missing(char, companion).empty?
          t('pf2e.companion_app_ok', :name => name_of(char, companion), :type => companion['type'].downcase)
        else
          t('pf2e.companion_app_missing', :missing => missing_named(char, companion))
        end

        "#{t('pf2e.companion_app_review')}%r%R%T#{status}"
      end

      # A companion's name, checked as a familiar's is (one word, letters, apostrophes and hyphens, not
      # restricted or a character's), with the messages about a companion, and never their familiar's name:
      # both can be in one encounter.
      module Names
        def self.name(raw, char)
          found = Familiar::Details.name(raw)

          if found.err?
            return Err.new(found.code.to_s.sub('familiar', 'companion').to_sym, found.key.sub('pf2e.familiar_', 'pf2e.companion_'), found.args)
          end

          familiar = Familiar.main_source(char) ? Familiar.details(char)['name'].to_s : ''
          return Err.new(:companion_name_familiar, 'pf2e.companion_name_familiar', 'name' => found.state) if familiar.casecmp?(found.state)

          found
        end

        # A familiar's name, refused when it is their animal companion's.
        def self.not_companion(char, name)
          companion = Companion.main(char)
          taken = companion ? Companion.name_of(char, companion).to_s : ''

          return Err.new(:familiar_name_companion, 'pf2e.familiar_name_companion', 'name' => name) if taken.casecmp?(name.to_s)

          Ok.new(:state => name)
        end
      end
    end
  end
end
