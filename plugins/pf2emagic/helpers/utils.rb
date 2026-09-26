module AresMUSH
  module Pf2emagic

    ANY_RANK = 'any'

    def self.any_rank?(key)
      key.to_s.casecmp?(ANY_RANK)
    end

    def self.adapted_spell?(char, charclass, spell_name)
      magic = char.magic
      return false unless magic

      entry = (magic.adapted_spells || {}).find { |name, _| name.to_s.casecmp?(spell_name.to_s) }
      return false unless entry

      klass = entry[1].is_a?(Hash) ? entry[1]['class'].to_s : ''

      klass.empty? || klass.casecmp?(charclass.to_s)
    end

    def self.is_caster?(char)
      magic = char.magic
      return false unless magic

      trad = magic.tradition
      trad = trad.delete('innate')
      innate_only = trad.empty?

      return false if innate_only && !Entries.innate?(magic)
      return true
    end

    def self.generate_spells_today(char)

      magic = char.magic

      spells_today = {}

      return t('pf2emagic.not_caster') unless magic

      class_list = magic.tradition.keys
      class_list.delete('innate')

      class_list.each do |cc|
        caster_type = Pf2emagic.get_caster_type(cc)
        next unless caster_type

        if caster_type == 'prepared'
          prepared_list = magic.spells_prepared
          spells_today[cc] = prepared_list[cc] || {}
        else
          spells_today[cc] = Entries.slots(magic, cc)
        end
      end

      # Only the ranked ones take a daily use; cantrips are cast at will.
      innate_spells_today = Entries.innate_ranked(magic).each_with_object({}) do |grant, today|
        rank = grant['level'].to_s

        today[rank] = Array(today[rank]) + [ grant['name'] ]
      end

      spells_today['innate'] = innate_spells_today unless innate_spells_today.empty?

      magic.update(spells_today: spells_today)

    end

    def self.do_refocus(target, enactor)

      # This is included because it validates the existence of a magic object.
      return t('pf2emagic.not_caster') unless is_caster?(target)

      magic = target.magic

      max = focus_pool_max(magic)
      current = focus_points_left(magic)

      return t('pf2emagic.no_focus_pool') if max.zero?

      # These checks are skipped if an admin is force-refocusing the target.
      if !enactor.is_admin?
        return t('pf2emagic.cant_refocus_pool') unless current < max

        last_refocus, current_time = magic.last_refocus, Time.now

        # Last refocus can be nil, use 0 epoch if it is

        last_refocus = Time.at(0) unless last_refocus

        elapsed = (current_time - last_refocus).to_i

        local_last_refocus = OOCTime.localtime(enactor, last_refocus)
        formatted_last_refocus = local_last_refocus.strftime("%-l:%M%P")

        return t('pf2emagic.cant_refocus_time', :time => formatted_last_refocus) unless (elapsed > 3600)
      end

      current = refocus_refills?(target) ? max : [ current + 1, max ].min

      magic.update(focus_pool: { 'current' => current })
      magic.update(last_refocus: Time.now)

      return nil
    end

    # A Refocus restores one point, or the whole pool for a character holding a feat marked
    # `refocus: refill` - Domain Focus and the class feats like it.
    def self.refocus_refills?(char)
      Pf2e::DraftSheet.of(char).feats_by_bucket.values.flatten.any? do |feat|
        details = Pf2e.get_feat_details(feat)

        !details.is_a?(String) && details[1]['refocus'].to_s == 'refill'
      end
    end

    def self.curriculum_spells(char, charclass, level)
      specialize = char.pf2_base_info['specialize']
      return [] if specialize.blank?

      specialty = Global.read_config('pf2e_specialty', charclass.to_s, specialize)
      return [] unless specialty.is_a?(Hash)

      curriculum = specialty['curriculum']
      return [] unless curriculum.is_a?(Hash)

      key = curriculum.keys.find { |k| k.to_s.casecmp?(level.to_s) }

      Array(key && curriculum[key]).compact.map(&:to_s)
    end

    def self.apply_stat_delta(current, value)
      return value unless value.is_a?(String) && value.strip.match?(/\A[+-]\d+\z/)

      current.to_i + value.strip.to_i
    end

    # The most points a focus pool holds: one per focus spell known that costs a point, up to three
    # (Player Core, Focus Spells). A spell two sources grant is one spell, and cantrips count for
    # nothing. Counted whenever it is asked for, so it follows every grant, rollback and correction.
    def self.focus_pool_max(magic)
      return 0 unless magic

      spells = Entries.focus_entries(magic).flat_map { |e| Array((e['known'] || {})['spell']) }

      spells.map(&:to_s).uniq(&:downcase).reject { |spell| focus_cantrip?(spell) }.size.clamp(0, 3)
    end

    # The points left, never more than the pool now holds.
    def self.focus_points_left(magic)
      return 0 unless magic

      [ (magic.focus_pool || {})['current'].to_i, focus_pool_max(magic) ].min
    end

    # A cantrip costs no point to cast. That is rank 0, or the cantrip trait: a bard's composition
    # cantrips have ranks above 0 and are cantrips all the same.
    def self.focus_cantrip?(spell)
      spells = Global.read_config('pf2e_spells') || {}
      key = spells.key?(spell) ? spell : spells.keys.find { |name| name.to_s.casecmp?(spell.to_s) }
      details = key && spells[key]

      return false unless details.is_a?(Hash)

      rank = details['base_level'].to_s.downcase

      rank == 'cantrip' || rank == '0' || Array(details['traits']).any? { |t| t.to_s.casecmp?('cantrip') }
    end

    def self.get_spell_details(term)
      result = get_spells_by_name(term)

      return t('pf2emagic.no_match', :item => "spells") if result.empty?
      return t('pf2e.multiple_matches', :element => 'spell') if result.size > 1

      spell_name = result.first

      spell_details = Global.read_config('pf2e_spells', spell_name)

      [ spell_name, spell_details ]
    end

    # Every spell a source casting `tradition` could put in a slot of `rank`.
    #
    # The same two rules SpellPick enforces when a pick is made - the tradition has to match, and a
    # spell cannot be learned above its own rank or in the wrong kind of slot - asked in advance,
    # so a player can read the list instead of guessing a name and being refused.
    def self.eligible_spells(tradition, rank)
      wanted = tradition.to_s.downcase
      cantrip_slot = rank.to_s.casecmp?('cantrip') || rank.to_s.to_i.zero?

      (Global.read_config('pf2e_spells') || {}).select do |_name, details|
        traditions = Array(details['tradition']).compact.map { |trad| trad.to_s.downcase }

        next false unless traditions.include?(wanted)

        base = details['base_level']
        spell_cantrip = base.to_s.casecmp?('cantrip') || base.to_s.to_i.zero?

        next spell_cantrip if cantrip_slot
        next false if spell_cantrip

        base.to_i <= rank.to_i
      end.keys.sort
    end

    def self.search_spells(search_type, term, operator='=')
      spell_info = Global.read_config('pf2e_spells')

      case search_type
      when 'name'
        match = spell_info.select { |k,v| k.upcase.match? term.upcase }
      when 'traits'
        match = spell_info.select { |k,v| v['traits'].include? term.downcase }
      when 'level'
        # Invalid operator defaults to ==.
        case operator
        when '<'
          match = spell_info.select { |k,v| (v['base_level'].to_i < term.to_i) && v['tradition'] }
        when '>'
          match = spell_info.select { |k,v| (v['base_level'].to_i > term.to_i) && v['tradition'] }
        else
          match = spell_info.select { |k,v| (v['base_level'].to_i == term.to_i) && v['tradition'] }
        end
      when 'tradition'
        match = spell_info.select { |k,v| v['tradition'] && (v['tradition'].include? term.downcase) }
      when 'school'
        match = spell_info.select { |k,v| v['school']&.include?(term.capitalize) }
      when 'bloodline'
        match = spell_info.select { |k,v| v['bloodline']&.include?(term.downcase) }
      when 'cast'
        match = spell_info.select { |k,v| v['cast']&.include? term.downcase }
      when 'description', 'desc', 'effect'
        match = spell_info.select { |k,v| v['effect'].upcase.match? term.upcase }
      end

      match.keys

    end

    def self.sort_level_spell_list(spells)
      # This function takes a hash and sorts it by integer-converted key.
      spells.sort {|a,b| a.first.to_i <=> b.first.to_i}.to_h
    end

    # The display name for a spell rank, the same everywhere a rank is shown regardless of the
    # caster's class.
    def self.rank_label(level)
      return 'Cantrip' if level.to_s.strip.casecmp?('cantrip') || level.to_i.zero?

      n = level.to_i
      suffix = case n % 10
               when 1 then 'st'
               when 2 then 'nd'
               when 3 then 'rd'
               else 'th'
               end

      "#{n}#{suffix}-rank"
    end

  end
end
