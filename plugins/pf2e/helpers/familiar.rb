module AresMUSH
  module Pf2e

    # A character's familiar. A familiar is a pet with special abilities (Player Core: "You gain the Pet
    # general feat, except that your pet has special abilities"), and in Emblem of Ea a character has one.
    #
    # What gives one is config: a feat flagged `familiar: true` ("you gain a familiar"), the Pet feat
    # (`pet: true`), or the Witch's Familiar class feature. A source may say what kind it is with
    # `familiar_kind:`:
    #
    #   spellbook   the witch's familiar, which contains their spells; it always becomes the familiar
    #   special     a familiar the feat makes into something (Alchemical Familiar's construct, Leshy
    #               Familiar's plant); it can't be taken over a familiar they already have
    #
    # Anything else is basic. Nobody may take a second source, except a spellbook one, which takes over
    # the familiar they had.
    module Familiar

      KINDS = %w{spellbook special basic}.freeze

      # The Witch's class feature, whose familiar is their spellbook.
      WITCH_FEATURE = 'Familiar'.freeze

      def self.source?(details)
        details.is_a?(Hash) && (details['familiar'] == true || details['pet'] == true)
      end

      def self.kind_of(details)
        kind = details.is_a?(Hash) ? details['familiar_kind'].to_s.downcase : ''

        KINDS.include?(kind) ? kind : 'basic'
      end

      # Each thing giving them a pet or familiar, counting this level's: [ { 'name', 'kind', 'feature' } ].
      def self.sources(char)
        feats = Pf2e.held_feat_details(char).select { |_name, details| source?(details) }.map do |name, details|
          { 'name' => name, 'kind' => kind_of(details), 'feature' => false }
        end

        witch = witch_feature?(char) ?
          [ { 'name' => WITCH_FEATURE, 'kind' => 'spellbook', 'feature' => true } ] : []

        witch + feats
      end

      # Whether their class features include the Witch's Familiar. Only the features count:
      # `Pf2e.holds_feature?` also counts feat-choice labels, and a Familiar feat picked through Natural
      # Ambition has the label "Familiar".
      def self.witch_feature?(char)
        DraftSheet.of(char).feature_names.any? { |feature| feature.to_s.strip.casecmp?(WITCH_FEATURE) }
      end

      def self.any?(char)
        !sources(char).empty?
      end

      # Whether taking a feat would give them a second pet or familiar. A spellbook familiar takes over the
      # one they have, so it is never refused for that.
      def self.blocks?(char, details)
        return false unless source?(details)
        return false if kind_of(details) == 'spellbook'

        any?(char)
      end

      # Why `blocks?` refused, for the player: the first source they already have.
      def self.block_message(char)
        held = sources(char).first

        held ? t('pf2e.familiar_one_only', :source => held['name']) : nil
      end

      # ----------------------------------------------------------------------------------------------
      # A spellbook familiar taking over
      #
      # Taking Witch Dedication over a familiar they have: a basic feat they picked (Pet, Familiar,
      # Animal Accomplice, Rat Familiar) is retrained in the same level, through `advance/retrain`. A
      # special one (Alchemical Familiar), or one a subclass or another feat handed over (the leaf order's
      # Leshy Familiar, Improved Familiar Attunement's Familiar, Animal Accomplice's Pet), becomes the witch
      # familiar and keeps its extras.
      # ----------------------------------------------------------------------------------------------

      # Feats something else gave them: another held feat's `grants: feat:`, their subclass's chargen feats,
      # and their subclass option's.
      def self.granted_feat_names(char)
        info = char.pf2_base_info || {}
        specialty = Global.read_config('pf2e_specialty', info['charclass'].to_s, info['specialize'].to_s) || {}
        option = ((specialty['choose'] || {})['options'] || {})[info['specialize_info'].to_s] || {}

        from_feats = Pf2e.held_feat_details(char).flat_map { |_name, details| Retrain.granted_feats(details) }
        from_specialty = Array((specialty['chargen'] || {})['feat']) + Array((option.is_a?(Hash) ? option['chargen'] || {} : {})['feat'])

        (from_feats + from_specialty).map { |name| name.to_s.upcase }
      end

      # The retrains a spellbook familiar taking over owes: [ { 'from', 'bucket', 'level', 'to' => nil } ] for
      # each basic feat on their sheet that gave them a familiar or pet and that they picked themselves.
      def self.owed_retrains(char)
        on_sheet = (char.pf2_feats || {}).values.flatten.map { |name| name.to_s.upcase }
        granted = granted_feat_names(char)

        sources(char).filter_map do |source|
          next if source['feature'] || source['kind'] != 'basic'

          name = source['name']
          next unless on_sheet.include?(name.upcase)
          next if granted.include?(name.upcase)

          taking = Retrain.taking(char, name)
          found = Pf2e.get_feat_details(name)
          also = found.is_a?(Array) ? Retrain.granted_feats(found[1]) : []

          # `from`: the feat retrained; `also`: the feats it gave, which go with it (Animal Accomplice's Pet).
          taking && taking.merge('from' => taking['feat'], 'also' => also, 'to' => nil)
        end
      end

      # The familiar a spellbook source taken now takes over: { 'source', 'name' }, or nil when they had
      # none. `feat` is the source being taken, left out by name because the draft that holds it may not
      # be saved yet. The name is the approved one, which they had to have to advance.
      def self.replaced(char, feat)
        other = sources(char).find { |one| !one['name'].to_s.casecmp?(feat.to_s) }
        return nil unless other

        approved = record(char)['approved']
        { 'source' => other['name'], 'name' => (approved.is_a?(Hash) ? approved['name'] : nil).to_s }
      end

      # FeatGain's row: a spellbook familiar taken in a draft stages the retrains it owes.
      def self.stage_retrains(char, advancement)
        owed = Array(advancement['retrains'])
        fresh = owed_retrains(char).reject { |one| owed.any? { |held| held['from'].casecmp?(one['from']) } }

        advancement['retrains'] = owed + fresh

        fresh.map do |one|
          [ 'pf2e.retrain_owed', { :feat => one['from'], :type => one['bucket'].gsub('charclass', 'class'),
                                   :level => one['level'] } ]
        end
      end

      # ----------------------------------------------------------------------------------------------
      # Details and approval
      #
      # `pf2_familiar` holds:
      #
      #   'pending'  => { 'name', 'species', 'form', … }   what the player has set and staff haven't approved
      #   'approved' => { 'name', 'species', 'form', …, 'source', 'by', 'at' }
      #   'job'      => the id of the request open for it
      #
      # Besides the three details, either may hold the picks (`Familiar::Choices`): 'specific' (a specific
      # familiar's name), 'choices' ({ 'skill' => 'Arcana' }), and 'pet_abilities' ([ { 'name', 'choice' } ]).
      #
      # Approved details are for one source: taking Witch Dedication over a familiar staff approved makes
      # the witch familiar the source, and it waits for approval again (with the old details to start
      # from). A change to approved details waits under `pending` while the approved ones stay in force.
      # ----------------------------------------------------------------------------------------------

      DETAILS = %w{name species form}.freeze
      PICKS = %w{specific choices pet_abilities}.freeze

      def self.record(char)
        held = char.pf2_familiar
        held.is_a?(Hash) ? Marshal.load(Marshal.dump(held)) : {}
      end

      # Where their familiar comes from: the spellbook source if they have one, which takes over any
      # other, or the first.
      def self.main_source(char)
        held = sources(char)
        held.find { |one| one['kind'] == 'spellbook' } || held.first
      end

      def self.approved_record(char)
        main = main_source(char)
        approved = record(char)['approved']

        return nil unless main && approved.is_a?(Hash)

        approved['source'].to_s == main['name'] ? approved : nil
      end

      def self.approved?(char)
        !approved_record(char).nil?
      end

      # Aeon Stone Reservoir: an aeon wyrd houses an aeon stone as its nucleus, and its master gains the
      # stone's benefits without investing it. So one invested aeon stone is left out of the invest limit.
      # Its resonant power isn't modeled.
      RESERVOIR = 'Aeon Wyrd'.freeze
      AEON_STONE = /\AAeon Stone\b/i

      def self.reservoir?(char)
        (approved_record(char) || {})['specific'].to_s == RESERVOIR
      end

      # How many of `items` count toward the invest limit: all of them, less one aeon stone for a master
      # whose aeon wyrd houses it.
      def self.invest_count(char, items)
        housed = reservoir?(char) && items.any? { |item| item.name.to_s.match?(AEON_STONE) }

        items.size - (housed ? 1 : 0)
      end

      # They have a familiar staff haven't approved for its current source. Everything but its spells
      # waits, and so does their next advancement.
      def self.awaiting_approval?(char)
        !main_source(char).nil? && !approved?(char)
      end

      # The details as they stand for the player: a change waiting for approval, else the approved ones,
      # else what an earlier source's approval left to start from. Picks appear once made.
      def self.details(char)
        held = record(char)
        shown = held['pending'] || held['approved'] || {}

        out = DETAILS.each_with_object({}) { |key, kept| kept[key] = shown[key].to_s }
        PICKS.each { |key| out[key] = shown[key] unless shown[key].blank? }
        out
      end

      # What approval still needs, as `familiar_field_*` keys.
      def self.missing(char)
        shown = details(char)
        DETAILS.select { |key| shown[key].blank? } + Choices.missing(char, shown)
      end

      def self.missing_named(char)
        missing(char).map { |key| t("pf2e.familiar_field_#{key}") }.join(', ')
      end

      # What cg/review and advance/review show of a familiar waiting to be set up: [ label, value ] for
      # each detail, then the picks and a pointer to sheet/familiar as plain lines. What's still missing is
      # said in their messages.
      def self.review_lines(char)
        shown = details(char)
        unset = t('pf2e.familiar_detail_unset')
        capitalized = ->(text) { text.to_s.sub(/\A\p{L}/) { |first| first.upcase } }

        lines = [ [ t('pf2e.familiar_sheet_label_name'), shown['name'].presence || unset ],
                  [ t('pf2e.familiar_sheet_label_species'), capitalized.call(shown['species'].presence || unset) ],
                  [ t('pf2e.familiar_sheet_label_form'), capitalized.call(shown['form'].presence || unset) ],
                  [ t('pf2e.familiar_sheet_label_specific'), shown['specific'] || t('pf2e.familiar_sheet_specific_none') ] ]

        picks = picks_text(shown)
        lines << t('pf2e.familiar_sheet_choices', :picks => picks) unless picks.empty?
        lines << t(Choices.plain_pet?(char) ? 'pf2e.familiar_review_note_pet' : 'pf2e.familiar_review_note')

        lines
      end

      # The review section's title: Pet for a plain pet.
      def self.review_title(char)
        Choices.plain_pet?(char) ? 'Pet' : 'Familiar'
      end

      # Details still to set before the familiar can go to staff, as `familiar_field_*` keys: none for a
      # character without one.
      def self.unfinished(char)
        main_source(char) ? missing(char) : []
      end

      # A Pet's abilities as the player writes them: "Fast Movement (land), Tough".
      def self.abilities_text(list)
        Array(list).map { |one| one['choice'].blank? ? one['name'] : "#{one['name']} (#{Array(one['choice']).join(', ')})" }.join(', ')
      end

      # The picks in a line, for the request and `app`: "Pipefox (skill: Arcana, language: Silya)".
      def self.picks_text(shown)
        parts = []
        made = (shown['choices'] || {}).map { |word, answer| "#{word}: #{answer}" }.join(', ')

        parts << (made.empty? ? shown['specific'] : "#{shown['specific']} (#{made})") if shown['specific']
        parts << made if !shown['specific'] && !made.empty?
        parts << abilities_text(shown['pet_abilities']) unless shown['pet_abilities'].blank?
        parts.join('; ')
      end

      # The abilities its approved details fix, as `Familiar::Stats.of` takes them: the free ones, the
      # chosen Plant or Fungus, a specific familiar's (with their choices, and its Porter), and a Pet's two.
      def self.fixed_abilities(char)
        approved = approved_record(char)
        return [] unless approved

        made = approved['choices'] || {}
        innate = Stats.innate(char)
        info = Stats.specific_config(approved['specific'])
        asked = Array(info['choices'])

        list = innate['abilities'].map { |name| { 'name' => name } }
        innate['choose'].each do |set|
          picked = Choices.find_in(set, made['ability'])
          list << { 'name' => picked } if picked
        end

        Array(info['abilities']).each do |name|
          word = asked.include?(name) ? Choices::WORDS[name] : nil
          list << (word && made[word] ? { 'name' => name, 'choice' => made[word] } : { 'name' => name })
        end

        porter = Choices.find_in(info['porter'], made['ability'])
        list << { 'name' => porter } if porter

        (list + Array(approved['pet_abilities'])).uniq
      end

      def self.job(char)
        id = record(char)['job']
        found = id.blank? ? nil : Job[id]

        found && found.is_open? ? found : nil
      end

      # Sets one detail, already validated. Returns the request it was written to, if one is open or opened.
      def self.set!(char, field, value)
        comment = t('pf2e.familiar_detail_comment', :field => t("pf2e.familiar_field_#{field}"), :value => value)

        change!(char, comment) { |pending| pending[field] = value }
      end

      # Changes what is pending, already validated, and says so in the request: the block is handed the
      # pending details to change. Returns the request, if one is open or opened.
      def self.change!(char, comment)
        held = record(char)
        pending = (held['pending'] || held['approved'] || {}).slice(*DETAILS, *PICKS)
        yield pending
        held['pending'] = pending.reject { |_key, value| value.blank? }
        char.update(:pf2_familiar => held)

        # Chargen approves the familiar with the application, so there is no request before that.
        return nil unless char.is_approved?

        found = job(char) || open_request!(char)
        Jobs.comment(found, char, comment, false) if found
        found
      end

      def self.request_category
        found = Global.read_config('pf2e', 'familiar_job_category')
        found.blank? ? Jobs.request_category : found
      end

      # The wiki page with the Patron Template a witch fills in for staff. Built on the portal's address
      # because game text goes to MUSH clients, which can't follow a relative link.
      PATRON_WIKI_PAGE = 'wiki/mechanics:patrons'.freeze

      def self.patron_wiki_url
        "#{Game.web_portal_url}/#{PATRON_WIKI_PAGE}"
      end

      # Whether their familiar comes from a patron (Witch Dedication or the Witch class), whose approval
      # request also approves the patron.
      def self.patron?(char)
        (main_source(char) || {})['kind'] == 'spellbook'
      end

      def self.summary(char)
        main = main_source(char)
        shown = details(char)
        none = t('pf2e.familiar_detail_unset')

        picks = picks_text(shown)

        t('pf2e.familiar_request_body', :char => char.name, :source => main ? main['name'] : none,
          :name => shown['name'].presence || none, :species => shown['species'].presence || none,
          :form => shown['form'].presence || none,
          :picks => picks.empty? ? '' : t('pf2e.familiar_request_picks', :picks => picks),
          :patron => patron?(char) ? t('pf2e.familiar_request_patron', :url => patron_wiki_url) : '')
      end

      # Opens the request staff approve the familiar in, if none is open. Returns it, or nil when the jobs
      # plugin refused.
      def self.open_request!(char)
        found = job(char)
        return found if found

        made = Jobs.create_job(request_category, t('pf2e.familiar_request_title', :char => char.name), summary(char), char)
        return nil unless made[:job]

        held = record(char)
        held['job'] = made[:job].id
        char.update(:pf2_familiar => held)

        made[:job]
      end

      # After a level: a familiar that needs approval gets a request. Returns the message for the player, or
      # nil when there is nothing to say.
      def self.after_level!(char)
        return nil unless awaiting_approval?(char)

        fresh = job(char).nil?
        found = open_request!(char)

        return nil unless found && fresh

        if patron?(char)
          return t('pf2e.familiar_request_opened_patron', :source => main_source(char)['name'], :number => found.id,
                   :url => patron_wiki_url)
        end

        t('pf2e.familiar_request_opened', :source => main_source(char)['name'], :number => found.id)
      end

      # Staff approve the details waiting. `by` is the staff character, or nil for the chargen approval.
      # Returns an Err naming what's missing, or Ok.
      def self.approve!(char, by:, close: true)
        main = main_source(char)
        return Err.new(:familiar_none, 'pf2e.familiar_none', 'char' => char.name) unless main

        unless missing(char).empty?
          return Err.new(:familiar_details_missing, 'pf2e.familiar_details_missing', 'char' => char.name, 'missing' => missing_named(char))
        end

        held = record(char)
        approver = by || Game.master.system_character

        held['approved'] = details(char).merge('source' => main['name'], 'by' => approver.name, 'at' => Time.now.to_i)
        held.delete('pending')

        open = job(char)
        held.delete('job')
        char.update(:pf2_familiar => held)

        Jobs.close_job(approver, open, t('pf2e.familiar_approved_comment', :name => held['approved']['name'])) if open && close

        Ok.new(:state => held)
      end

      # Staff send the details back with a reason, in the request. The request stays open.
      def self.reject!(char, by:, reason:)
        return Err.new(:familiar_none, 'pf2e.familiar_none', 'char' => char.name) unless main_source(char)

        found = job(char) || open_request!(char)
        return Err.new(:familiar_no_request, 'pf2e.familiar_no_request', 'char' => char.name) unless found

        Jobs.comment(found, by, t('pf2e.familiar_rejected_comment', :reason => reason), false)

        Ok.new(:state => record(char))
      end

      # Chargen approval approves the familiar with the application.
      def self.approve_with_app!(char)
        return unless main_source(char)

        # An application approved with details missing leaves the familiar to finish in a request.
        open_request!(char) if approve!(char, :by => nil, :close => false).err?
      end

      # The familiar check in `app`'s character sheet section, laid out as the sheet check is: what is
      # checked, then whether it passed. Nil for a character with no familiar.
      def self.app_review(char)
        return nil unless main_source(char)

        status = missing(char).empty? ? t('pf2e.familiar_app_ok') : t('pf2e.familiar_app_missing', :missing => missing_named(char))

        "#{t('pf2e.familiar_app_review')}%r%R%T#{status}"
      end
    end
  end
end
