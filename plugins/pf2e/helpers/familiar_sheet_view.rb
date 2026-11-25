module AresMUSH
  module Pf2e
    module Familiar

      # What sheet/familiar shows, as plain values: a title, and sections of rows. A row is a list of cells
      # laid out side by side (a cell is [ label, value ]), or a string on a line of its own. The template
      # only lays them out.
      #
      # A familiar awaiting approval shows what is waiting and its spells. An approved one shows its stats,
      # what its details fix (a plain pet's two abilities, or a specific familiar's), today's abilities, its
      # spells and the rules that bind it.
      #
      # `familiar` is its record in an encounter (e/sheet/familiar): the sheet then opens with what it has
      # in the fight, and its stats are as they stand there, with its own conditions and its master's
      # state in the encounter beneath them.
      module SheetView

        def self.build(char, familiar: nil)
          main = Familiar.main_source(char)
          return nil unless main

          approved = Familiar.approved_record(char)
          shown = approved || Familiar.details(char)
          called = shown['name'].presence
          name = called || t('pf2e.familiar_sheet_unnamed')
          pet = Choices.plain_pet?(char)

          # What a sentence calls it: its name, or "your familiar" before it has one.
          context = { 'char' => char, 'main' => main, 'approved' => approved, 'name' => name, 'pet' => pet,
                      'familiar' => familiar,
                      'start' => called || t('pf2e.familiar_sheet_yours_start'), 'mid' => called || t('pf2e.familiar_sheet_yours_mid') }
          sections = approved ? approved_sections(context) : waiting_sections(context)

          { 'title' => t(pet ? 'pf2e.familiar_sheet_title_pet' : 'pf2e.familiar_sheet_title', :name => name, :char => char.name),
            'sections' => sections.compact }
        end

        # `notes` are lines said after the rows, beneath a divider, as cg/review says its messages last.
        def self.section(title, rows, notes = [])
          { 'title' => title, 'rows' => rows, 'notes' => notes }
        end

        def self.signed(value)
          value.to_i.negative? ? value.to_i.to_s : "+#{value.to_i}"
        end

        def self.capitalized(text)
          text.to_s.sub(/\A\p{L}/) { |first| first.upcase }
        end

        # ------------------------------------------------------------------------------------------------
        # Waiting for approval
        # ------------------------------------------------------------------------------------------------

        def self.waiting_sections(context)
          char = context['char']
          shown = Familiar.details(char)
          unset = t('pf2e.familiar_detail_unset')
          job = Familiar.job(char)

          waits = if job then t('pf2e.familiar_sheet_waiting_request', :number => job.id)
                  elsif !char.is_approved? then t('pf2e.familiar_sheet_waiting_app')
                  else t('pf2e.familiar_sheet_waiting')
                  end
          # Only a witch's familiar has spells, which work before approval.
          if context['main']['kind'] == 'spellbook'
            waits = "#{waits} #{t('pf2e.familiar_sheet_waiting_spells', :name => context['mid'])}"
          end

          rows = [ [ [ t('pf2e.familiar_sheet_label_name'), shown['name'].presence || unset ],
                     [ t('pf2e.familiar_sheet_label_species'), capitalized(shown['species'].presence || unset) ] ],
                   [ [ t('pf2e.familiar_sheet_label_form'), capitalized(shown['form'].presence || unset) ],
                     [ t('pf2e.familiar_sheet_label_specific'), shown['specific'] || t('pf2e.familiar_sheet_specific_none') ] ] ]
          picks = Familiar.picks_text(shown)
          rows << t('pf2e.familiar_sheet_choices', :picks => picks) unless picks.empty?

          notes = []
          notes << t('pf2e.familiar_sheet_missing', :missing => Familiar.missing_named(char)) unless Familiar.missing(char).empty?
          notes += [ waits, t('pf2e.familiar_sheet_change') ]
          notes << t('pf2e.familiar_sheet_help_chargen') if !job && !char.is_approved?

          [ section(t('pf2e.familiar_sheet_section_waiting'), rows, notes), spells_section(context) ]
        end

        # ------------------------------------------------------------------------------------------------
        # Approved
        # ------------------------------------------------------------------------------------------------

        def self.approved_sections(context)
          char = context['char']
          approved = context['approved']
          familiar = context['familiar']
          # In an encounter, its master as they stand there.
          master = familiar&.master || char
          stats = stats(master, approved)
          stats = in_fight(stats, familiar) if familiar
          context = context.merge('stats' => stats)

          [ familiar ? encounter_section(context) : nil,
            basic_section(context), stats_section(context), saves_section(context), skills_section(context),
            context['pet'] ? pet_section(context) : nil, specific_section(context), activities_section(context, master),
            context['pet'] ? nil : today_section(context), spells_section(context), notes_section(context) ]
        end

        # What its master's feats let it do - Shed Spirit and the like - with its master's figures, as they
        # stand in the encounter where it is in one.
        def self.activities_section(context, master)
          rows = Activities.sheet_lines(master, context['name'])
          return nil if rows.empty?

          section(t('pf2e.familiar_sheet_section_activities'), rows, [ t('pf2e.familiar_sheet_activities_how', :name => context['name']) ])
        end

        # An approved familiar's stats today, from its master's: `sheet/familiar` and the profile's Familiar
        # tab both read them here.
        def self.stats(master, approved)
          Stats.of(master, Daily.abilities_today(master), :form => approved['form'].presence || 'land',
                   :specific => approved['specific'], :options => Daily.options(master))
        end

        # ------------------------------------------------------------------------------------------------
        # In an encounter
        # ------------------------------------------------------------------------------------------------

        # Its stats as the creature code reads them, which counts its own conditions and effects. A skill
        # those move away from the rest is listed on its own.
        def self.in_fight(stats, npc)
          read = ->(kind, name = nil) { (Npcs.stat(npc, kind, name) || {})['total'].to_i }
          others = (Global.read_config('pf2e_skills') || {}).keys - stats['skills'].keys
          other_values = others.to_h { |skill| [ skill, read.call('skill', skill) ] }
          usual = other_values.values.tally.max_by { |_value, count| count }&.first || stats['other_skills']

          stats.merge('hp' => "#{npc.hp_left} / #{npc.max_hp}",
                      'ac' => read.call('ac'),
                      'perception' => read.call('perception'),
                      'saves' => stats['saves'].keys.to_h { |save| [ save, read.call('save', save) ] },
                      'skills' => stats['skills'].keys.to_h { |skill| [ skill, read.call('skill', skill) ] }
                                    .merge(other_values.reject { |_skill, value| value == usual }),
                      'skilled' => stats['skills'].keys - Stats::KEPT_SKILLS,
                      'other_skills' => usual)
        end

        def self.encounter_section(context)
          npc = context['familiar']
          none = t('pf2e.familiar_sheet_none')
          effects = ActiveEffects.on(npc).map { |effect| "#{effect.name} (#{ActiveEffects.remaining(effect)})" }

          section(t('pf2e.familiar_sheet_section_encounter', :id => npc.encounter&.id), [
            [ [ t('pf2e.familiar_sheet_label_id'), "##{npc.number}" ], [ t('pf2e.familiar_sheet_label_actions'), actions_text(npc) ] ],
            [ [ t('pf2e.familiar_sheet_label_conditions'), Pf2e.condition_labels(npc, false).join(', ').presence || none ] ],
            [ [ t('pf2e.familiar_sheet_label_effects'), effects.join(', ').presence || none ] ]
          ])
        end

        # `1 of 2 used (Commanded)`.
        def self.actions_text(npc)
          state = if Minion.commanded?(npc) then t('pf2e.familiar_sheet_commanded')
                  elsif Minion.turn_actions(npc).positive? then Minion::INDEPENDENT
                  else t('pf2e.familiar_sheet_not_commanded')
                  end

          t('pf2e.familiar_sheet_actions', :used => TurnState.turn(npc)['actions'].to_i, :total => TurnState.actions(npc),
                                           :state => state)
        end

        def self.source_label(context)
          main = context['main']
          main['feature'] ? (context['char'].pf2_base_info || {})['charclass'].to_s : main['name']
        end

        def self.basic_section(context)
          approved = context['approved']
          stats = context['stats']
          traits = stats['traits'].map { |trait| capitalized(trait) }.sort.join(', ')

          section(t('pf2e.familiar_sheet_section_basic'), [
            [ [ t('pf2e.familiar_sheet_label_species'), capitalized(approved['species']) ],
              [ t('pf2e.familiar_sheet_label_form'), capitalized(approved['form']) ] ],
            [ [ t('pf2e.familiar_sheet_label_source'), source_label(context) ],
              [ t('pf2e.familiar_sheet_label_level'), stats['level'].to_s ] ],
            [ [ t('pf2e.familiar_sheet_label_size'), capitalized(stats['size']) ],
              [ t('pf2e.familiar_sheet_label_traits'), traits ] ]
          ])
        end

        def self.feet(movement, value, named: true)
          named ? t('pf2e.familiar_sheet_speed_named', :movement => movement, :feet => value) : t('pf2e.familiar_sheet_speed', :feet => value)
        end

        def self.stats_section(context)
          stats = context['stats']
          speeds = stats['speeds']
          none = t('pf2e.familiar_sheet_none')
          land = speeds['land'] ? feet('land', speeds['land'], :named => false) : none
          special = speeds.except('land').map { |movement, value| feet(movement, value) }.join(', ')

          section(t('pf2e.familiar_sheet_section_stats'), [
            [ [ t('pf2e.familiar_sheet_label_hp'), stats['hp'].to_s ], [ t('pf2e.familiar_sheet_label_ac'), stats['ac'].to_s ] ],
            [ [ t('pf2e.familiar_sheet_label_perception'), signed(stats['perception']) ],
              [ t('pf2e.familiar_sheet_label_attack'), signed(stats['attack']) ] ],
            [ [ t('pf2e.familiar_sheet_label_speed'), land ] ],
            [ [ t('pf2e.familiar_sheet_label_movement'), special.presence || none ] ],
            [ [ t('pf2e.familiar_sheet_label_senses'), stats['senses'].join(', ') ] ]
          ])
        end

        def self.saves_section(context)
          stats = context['stats']
          rows = [ stats['saves'].map { |save, value| [ save, signed(value) ] } ]

          { 'resistances' => stats['resistances'], 'weaknesses' => stats['weaknesses'] }.each do |kind, held|
            next if held.empty?

            rows << [ [ t("pf2e.familiar_sheet_label_#{kind}"), held.map { |one| "#{one['type'].tr('-', ' ')} #{one['value']}" }.join(', ') ] ]
          end
          unless stats['immunities'].empty?
            rows << [ [ t('pf2e.familiar_sheet_label_immunities'), stats['immunities'].map { |one| one.tr('-', ' ') }.join(', ') ] ]
          end

          section(t('pf2e.familiar_sheet_section_saves'), rows)
        end

        def self.skills_section(context)
          stats = context['stats']
          skilled = stats['skilled'] || (stats['skills'].keys - Stats::KEPT_SKILLS)

          cells = stats['skills'].map do |skill, value|
            label = skilled.include?(skill) ? t('pf2e.familiar_sheet_skilled', :value => signed(value)) : signed(value)
            [ skill, label ]
          end

          rows = cells.each_slice(3).to_a
          rows << [ [ t('pf2e.familiar_sheet_label_other_skills'), signed(stats['other_skills']) ] ]

          section(t('pf2e.familiar_sheet_section_skills'), rows)
        end

        def self.pet_section(context)
          held = Array(context['approved']['pet_abilities'])

          section(t('pf2e.familiar_sheet_section_pet'), [ Familiar.abilities_text(held) ])
        end

        # What a specific familiar gives, and its own abilities.
        def self.specific_section(context)
          approved = context['approved']
          name = approved['specific']
          return nil if name.blank?

          info = Stats.specific_config(name)
          made = approved['choices'] || {}
          given = Familiar.fixed_abilities(context['char']).select do |one|
            Array(info['abilities']).include?(one['name']) || Array(info['porter']).include?(one['name'])
          end

          unchosen = t('pf2e.familiar_sheet_unchosen')
          fills = { :name => context['name'], :skill => made['skill'] || unchosen, :language => made['language'] || unchosen,
                    :ability => (made['ability'] || unchosen).downcase }

          rows = [ t('pf2e.familiar_sheet_gives', :abilities => Familiar.abilities_text(given)) ]
          rows += (info['specials'] || {}).map { |special, text| "#{special}: #{format(text.to_s, fills)}" }

          title = t('pf2e.familiar_sheet_section_specific', :specific => name, :uses => info['uses'].to_i,
                    :name => context['name'], :count => Stats.ability_count(context['char']))
          section(title, rows)
        end

        def self.today_section(context)
          char = context['char']
          today = Daily.today(char)
          catalogue = Daily.catalogue
          innate = Stats.innate(char)
          patron = Stats.patron_ability(char)
          free = Familiar.fixed_abilities(char).map { |one| one['name'] } & (innate['abilities'] + innate['choose'].flatten) - [ patron ]

          rows = []
          if today.empty?
            rows << t('pf2e.familiar_sheet_none_today')
          else
            shown = today.map do |one|
              one['name'] == Daily::REINFORCED ? one.merge('name' => t('pf2e.familiar_sheet_reinforced')) : one
            end
            familiar, master = shown.partition { |one| (catalogue[one['name']] || {})['kind'] != 'master' }

            rows << [ [ t('pf2e.familiar_sheet_label_familiar'), Familiar.abilities_text(familiar) ] ] unless familiar.empty?
            rows << [ [ t('pf2e.familiar_sheet_label_master'), Familiar.abilities_text(master) ] ] unless master.empty?
          end

          rows << [ [ t('pf2e.familiar_sheet_label_patron'), patron ] ] if patron
          rows << [ [ t('pf2e.familiar_sheet_label_free'), free.join(', ') ] ] unless free.empty?
          rows << t('pf2e.familiar_sheet_change_today', :name => context['name']) unless today.empty?

          title = t('pf2e.familiar_sheet_section_today', :picked => today.size, :count => Daily.budget(char))
          section(title, rows)
        end

        # The spells a witch's familiar contains, counted from their witch spell list.
        def self.spells_section(context)
          main = context['main']
          return nil unless main['kind'] == 'spellbook'

          char = context['char']
          source = FamiliarView.spell_source(char)
          known = char.magic ? Pf2emagic::Entries.known(char.magic, source) : {}
          counted = known.each_with_object(Hash.new(0)) do |(rank, spells), out|
            out[rank.to_s.casecmp?('cantrip') ? 'cantrips' : 'spells'] += Array(spells).count { |one| !one.to_s.casecmp?(Pf2emagic::Entries::OPEN) }
          end

          section(t('pf2e.familiar_sheet_section_spells'),
                  [ t('pf2e.familiar_sheet_spells', :name => context['start'], :cantrips => counted['cantrips'], :spells => counted['spells']) ])
        end

        def self.notes_section(context)
          section(t('pf2e.familiar_sheet_section_notes'), [ t('pf2e.familiar_sheet_notes', :name => context['name']) ])
        end
      end
    end
  end
end
