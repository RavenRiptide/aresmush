module AresMUSH
  module Pf2e

    # A character's animal companion (Player Core pp. 206-211), as their feats and those feats' choices say it
    # is. Nothing about it is stored apart from them: the type is the companion feat's choice ("Wolf",
    # "Horse (Large)"), nimble or savage is the incredible feat's, and each specialization is a specialized
    # feat's ("Racer (land)", "Auspice"). So chargen, advancement, undo and rollback handle it as any choice.
    #
    # Config marks the feats: `companion: true` gives one (Animal Companion, Animal Companion (Ranger),
    # Faithful Steed, which adds `companion_mount: true`); `companion_stage:` mature, incredible or specialized
    # advances it; `companion_grants:` is what another feat gives it (Fell Rider, Stealthy Companion, Rough
    # Rider); `bonded_animal: true` is Bonded Animal, which a companion and it each refuse.
    #
    # A character has one companion. Everything takes a list, so the Beastmaster's several can come later.
    module Companion

      STAGES = %w{mature incredible specialized}.freeze
      LABEL = /\A(.+?) \((.+)\)\z/.freeze

      def self.source?(details)
        details.is_a?(Hash) && details['companion'] == true
      end

      def self.bonded_animal?(details)
        details.is_a?(Hash) && details['bonded_animal'] == true
      end

      # "Horse (Large)" is [ 'Horse', 'Large' ]; "Wolf" is [ 'Wolf', nil ].
      def self.split_label(label)
        found = LABEL.match(label.to_s.strip)
        found ? [ found[1], found[2] ] : [ label.to_s.strip.presence, nil ]
      end

      # ----------------------------------------------------------------------------------------------
      # The pure core
      # ----------------------------------------------------------------------------------------------

      # The companions `held` (feat name => details, in order) gives, as Stats.of takes them, plus `id`,
      # `source`, `pending` (stages whose choice is still open) and `waiting` (each such stage => the feat whose
      # choice it waits on). `labels_for` gives a feat's choice labels;
      # `open` names the feats whose choice is open; `servitors` is the deity's, which Auspice takes.
      def self.assemble(held, labels_for, open: [], servitors: nil)
        source = held.find { |_name, details| source?(details) }
        return [] unless source

        name = source[0]
        type, size = split_label(labels_for.call(name).first)
        staged = held.select { |_feat, details| STAGES.include?(details['companion_stage'].to_s) }
        by_stage = ->(stage) { staged.select { |_feat, details| details['companion_stage'] == stage }.map(&:first) }

        path = by_stage.call('incredible').flat_map { |feat| labels_for.call(feat) }.first
        specializations = by_stage.call('specialized').flat_map { |feat| labels_for.call(feat) }.map do |label|
          named, choice = split_label(label)
          { 'name' => named, 'choice' => named == 'Auspice' ? servitors : choice }
        end

        open_feats = staged.select { |feat, _details| open.any? { |one| one.to_s.casecmp?(feat) } }
        pending = open_feats.map { |_feat, details| details['companion_stage'] }.uniq
        waiting = open_feats.each_with_object({}) { |(feat, details), out| out[details['companion_stage']] ||= feat }

        [ { 'id' => name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/-\z/, ''),
            'source' => name,
            'type' => type,
            'size' => size,
            'mature' => !staged.empty?,
            'path' => path.to_s.downcase.presence,
            'specializations' => specializations,
            'pending' => pending,
            'waiting' => waiting } ]
      end

      # What the held feats' `companion_grants` give together, as Stats.of takes them.
      def self.merged_grants(held)
        held.each_with_object({ 'skills' => {}, 'raise_with' => {}, 'mount' => [] }) do |(_name, details), out|
          given = details['companion_grants']
          next unless given.is_a?(Hash)

          (given['skills'] || {}).each do |skill, word|
            out['skills'][skill] = [ out['skills'][skill], word ].compact.max_by { |rank| Companion::Stats.rank_of(rank) }
          end
          (given['raise_with'] || {}).each { |special, skills| out['raise_with'][special] = Array(out['raise_with'][special]) + Array(skills) }
          out['mount'].concat(Array(given['mount']))
        end
      end

      # The type choice's labels: each type a player may choose, "Horse (Medium)" and "Horse (Large)" for a
      # type with sizes. `mount_only` keeps types with the mount special and those `mounts` names. `allowed`
      # says whether an uncommon type's `access` is met; an uncommon type without `access` is never offered.
      def self.type_labels(catalogue, mount_only: false, mounts: [], allowed: ->(_access) { false })
        (catalogue['types'] || {}).sort.flat_map do |name, info|
          next [] if mount_only && info['mount'] != true && !Array(mounts).include?(name)
          next [] if info['rarity'].to_s == 'uncommon' && !(info['access'] && allowed.call(info['access']))

          sizes = Array(info['sizes'])
          sizes.empty? ? [ name ] : sizes.map { |size| "#{name} (#{size})" }
        end
      end

      # A specialized feat's labels: each specialization the companion doesn't have, "Racer (land)" for each
      # Speed it could race with, and Auspice only through the feats it names and for a deity with servitors.
      def self.specialization_labels(catalogue, held:, speeds:, feat:, servitors: nil)
        (catalogue['specializations'] || {}).flat_map do |name, info|
          next [] if Array(held).include?(name)
          next [] if info['only_for'] && !Array(info['only_for']).include?(feat.to_s)
          next [] if name == 'Auspice' && servitors.blank?

          choice = info['choice'] || {}
          next [ name ] unless choice['from'] == 'speeds'

          (Array(choice['only']) & Array(speeds)).map { |speed| "#{name} (#{speed})" }
        end
      end

      # ----------------------------------------------------------------------------------------------
      # Reading a character
      # ----------------------------------------------------------------------------------------------

      # Feat name => details for what they hold: counting an open level's feats (`draft`), or only what is
      # committed.
      def self.held(char, draft: true)
        names = if draft
          DraftSheet.of(char).feat_names
        else
          (char.pf2_feats || {}).values.flatten.map { |name| name.to_s.upcase }.uniq
        end

        feats = Global.read_config('pf2e_feats') || {}
        by_upcase = feats.keys.each_with_object({}) { |key, out| out[key.to_s.upcase] = key }

        names.filter_map do |name|
          key = by_upcase[name.to_s.upcase]
          key && feats[key].is_a?(Hash) ? [ key, feats[key] ] : nil
        end
      end

      def self.labels_reader(char, draft: true)
        if draft
          ->(name) { Pf2e.choice_labels_for(char, name) }
        else
          recorded = Pf2e.recorded_choices(char)
          ->(name) { recorded.select { |choice, _label, _level| choice.to_s.casecmp?(name.to_s) }.map { |_choice, label, _level| label } }
        end
      end

      def self.servitors(char)
        deity = (char.pf2_faith || {})['deity']
        deity.blank? ? nil : Global.read_config('pf2e_deities', deity.to_s, 'servitors')
      end

      def self.list(char, draft: true)
        open = draft ? Pf2e.pending_feat_choices(char).select { |_name, slots| slots.any? { |one| one.to_s.casecmp?('open') } }.keys : []

        assemble(held(char, :draft => draft), labels_reader(char, :draft => draft), :open => open, :servitors => servitors(char))
      end

      def self.level_of(char, draft: true)
        draft ? DraftSheet.of(char).level : char.pf2_level.to_i
      end

      # A companion's statistics as the character stands, with what it wears, or nil before its type is chosen.
      def self.stats(char, companion, draft: true)
        return nil unless companion && companion['type']

        Stats.of(companion, :level => level_of(char, :draft => draft), :grants => merged_grants(held(char, :draft => draft)),
                 **Gear.stat_args(char, companion))
      end

      # ----------------------------------------------------------------------------------------------
      # The choices
      # ----------------------------------------------------------------------------------------------

      # The types the companion feat `feat` offers them.
      def self.type_options(char, feat)
        details = Global.read_config('pf2e_feats', feat.to_s) || {}
        level = level_of(char)

        type_labels(Stats.catalogue,
                    :mount_only => details['companion_mount'] == true,
                    :mounts => merged_grants(held(char))['mount'],
                    :allowed => ->(access) { Pf2e.meets_prereqs?(char, access, level) == true })
      end

      # The specializations the specialized feat `feat` offers their companion.
      def self.specialization_options(char, feat)
        companion = list(char).first
        found = stats(char, companion)
        return [] unless found

        specialization_labels(Stats.catalogue,
                              :held => companion['specializations'].map { |one| one['name'] },
                              :speeds => found['speeds'].keys,
                              :feat => feat,
                              :servitors => servitors(char))
      end

      # ----------------------------------------------------------------------------------------------
      # One companion, and no bonded animal beside it
      # ----------------------------------------------------------------------------------------------

      # The companion feats they hold.
      def self.sources(char)
        held(char).select { |_name, details| source?(details) }.map(&:first)
      end

      def self.bonded?(char)
        held(char).any? { |_name, details| bonded_animal?(details) }
      end

      # Why taking a feat is refused, as a locale key, or nil: a second companion, a companion beside
      # Bonded Animal, or Bonded Animal beside a companion ("You can't have both a bonded animal and an
      # animal companion").
      def self.block_reason(char, details)
        if source?(details)
          return 'pf2e.companion_one_only' unless sources(char).empty?
          return 'pf2e.companion_bonded_animal' if bonded?(char)
        elsif bonded_animal?(details)
          return 'pf2e.companion_bonded_animal' unless sources(char).empty?
        end

        nil
      end

      def self.blocks?(char, details)
        !block_reason(char, details).nil?
      end

      def self.block_message(char, details)
        reason = block_reason(char, details)
        reason ? t(reason, :source => sources(char).first) : nil
      end

      # ----------------------------------------------------------------------------------------------
      # What cg/review shows
      # ----------------------------------------------------------------------------------------------

      # [ label, value ] pairs, then plain lines, for the companion they're building; empty without one. Its
      # stats are left to sheet/companion, which the last line points to once it has a type. What is still
      # missing is said in cg/review's messages, not here.
      def self.review_lines(char)
        companion = list(char).first
        return [] unless companion

        name = name_of(char, companion)
        lines = [ [ t('pf2e.companion_label_name'), name || t('pf2e.companion_name_unset') ] ]

        found = stats(char, companion)
        unless found
          lines << [ t('pf2e.companion_label_type'), t('pf2e.companion_type_unchosen') ]
          return lines
        end

        lines << [ t('pf2e.companion_label_type'), "#{companion['type']} (#{found['stage']})" ]
        lines << t('pf2e.companion_review_app', :name => name) if name && !char.is_approved?
        lines << t('pf2e.companion_review_note')
        lines
      end

      def self.signed(value)
        value.to_i.negative? ? value.to_s : "+#{value}"
      end

      def self.damage(attack)
        modifier = attack['modifier'].to_i
        bonus = modifier.zero? ? '' : (modifier.positive? ? "+#{modifier}" : modifier.to_s)
        text = "#{attack['dice']}#{attack['die']}#{bonus} #{attack['damage_type']}"
        attack['extra'] ? "#{text} plus #{attack['extra']}" : text
      end
    end
  end
end
