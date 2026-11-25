module AresMUSH
  module Pf2e
    module Companion

      # The wiki page with every companion type's stats. Built on the portal's address, because game text goes
      # to MUSH clients, which can't follow a relative link.
      WIKI_PAGE = 'wiki/mechanics:animal-companions'.freeze

      def self.wiki_url
        "#{Game.web_portal_url}/#{WIKI_PAGE}"
      end

      # What sheet/companion shows, as plain values in the shape the familiar sheet's template lays out: a title,
      # and sections of rows. A row is a list of cells side by side (a cell is [ label, value ]), or a string on
      # a line of its own.
      #
      # It shows the companion they have: while a level is open, the one they had before it (advance/review
      # shows what the level changes). A companion waiting for approval opens with what waits; one with no type
      # yet shows only how to choose it.
      module SheetView

        ATTRIBUTES = [ [ 'Strength', 'Str' ], [ 'Dexterity', 'Dex' ], [ 'Constitution', 'Con' ],
                       [ 'Intelligence', 'Int' ], [ 'Wisdom', 'Wis' ], [ 'Charisma', 'Cha' ] ].freeze

        # `npc` is its record in an encounter (e/sheet/companion): the sheet then opens with what it has there,
        # and its figures are as they stand in the fight, its own conditions and effects counted. An approved
        # companion is the only kind that joins, so approval and replacement are left out.
        def self.build(char, npc: nil)
          draft = npc.nil? && !char.advancing
          companion = Companion.list(char, :draft => draft).first
          return nil unless companion

          name = npc ? npc.name : Companion.name_of(char, companion)
          title = name ? t('pf2e.companion_sheet_title', :name => name, :char => char.name) :
                         t('pf2e.companion_sheet_title_unnamed', :char => char.name)

          found = Companion.stats(char, companion, :draft => draft)
          found = in_fight(found, npc) if found && npc
          context = { 'char' => char, 'companion' => companion, 'stats' => found, 'name' => name, 'npc' => npc,
                      'subject' => name || t('pf2e.companion_subject_unnamed'),
                      'mid' => name || t('pf2e.companion_subject_unnamed_mid') }

          sections = npc ? [ encounter_section(context) ] : [ status_section(context), replacement_section(context) || waiting_section(context) ]
          sections.concat(found ? stat_sections(context) : [ unchosen_section(context) ])

          { 'title' => title, 'sections' => sections.compact }
        end

        def self.section(title, rows, notes = [])
          { 'title' => title, 'rows' => rows, 'notes' => notes }
        end

        def self.capitalized(text)
          text.to_s.sub(/\A\p{L}/) { |first| first.upcase }
        end

        def self.traits(list)
          Array(list).map { |trait| capitalized(trait) }.join(', ')
        end

        # ------------------------------------------------------------------------------------------------
        # Waiting
        # ------------------------------------------------------------------------------------------------

        def self.waiting_section(context)
          char = context['char']
          return nil if Companion.approved?(char, context['companion'])

          name = context['name']
          rows = [ [ [ t('pf2e.companion_label_name'), name || t('pf2e.companion_name_unset') ] ] ]
          job = Companion.job(char, context['companion'])

          rows << if !name
            t('pf2e.companion_sheet_waiting_unnamed')
          elsif job
            t('pf2e.companion_sheet_waiting_request', :number => job.id, :name => name)
          elsif !char.is_approved?
            t('pf2e.companion_sheet_waiting_app', :name => name)
          else
            t('pf2e.companion_sheet_waiting', :name => name)
          end

          section(t('pf2e.companion_sheet_section_waiting'), rows)
        end

        # A companion staff marked dead, until it's raised or replaced.
        def self.status_section(context)
          char = context['char']
          return nil unless Companion.dead?(char, context['companion']) && !Companion.replacement(char, context['companion'])

          section(t('pf2e.companion_sheet_section_status'), [ t('pf2e.companion_sheet_dead', :subject => context['subject']) ])
        end

        # A replacement waiting for staff: who it replaces, what it will be, the choices made and left, and the
        # request. The old companion's stats follow, because it stays in force until staff approve.
        def self.replacement_section(context)
          char = context['char']
          companion = context['companion']
          found = Companion.replacement(char, companion)
          return nil unless found

          old = found['from'].to_s
          type = Companion.replacement_type(char, companion).downcase
          new_name = Companion.entry(char, companion).dig('pending', 'name')

          lines = []
          lines << t('pf2e.companion_sheet_died', :subject => old) if Companion.dead?(char, companion)
          lines << (new_name ? t('pf2e.companion_sheet_replacing_named', :old => old, :type => type, :name => new_name) :
                               t('pf2e.companion_sheet_replacing', :old => old, :type => type))

          made = (found['choices'] || {}).flat_map { |feat, labels| Array(labels).map { |label| "#{feat}: #{label}" } }
          lines << t('pf2e.companion_sheet_replacing_choices', :choices => made.join(', ')) unless made.empty?

          left = Companion.choices_left(char, companion).uniq
          lines << t('pf2e.companion_sheet_replacing_choose', :feats => left.join(', ')) unless left.empty?
          lines << t('pf2e.companion_sheet_replacing_name') unless new_name

          job = Companion.job(char, companion)
          lines << t('pf2e.companion_sheet_replacing_request', :number => job.id, :old => old) if job

          section(t('pf2e.companion_sheet_section_waiting'), lines)
        end

        def self.unchosen_section(context)
          char = context['char']
          command = char.advancing ? 'advance/option' : 'cg/option'

          section(t('pf2e.companion_sheet_section_type'),
                  [ t('pf2e.companion_sheet_choose_type', :command => command, :feat => context['companion']['source']),
                    t('pf2e.companion_sheet_wiki', :url => Companion.wiki_url) ])
        end

        # ------------------------------------------------------------------------------------------------
        # The companion
        # ------------------------------------------------------------------------------------------------

        # ------------------------------------------------------------------------------------------------
        # In an encounter
        # ------------------------------------------------------------------------------------------------

        # Its figures as the creature code reads them: hit points left of its most, and AC, Perception, saves,
        # skills and attack bonuses with its own conditions and effects. Attack bonuses are a first Strike's,
        # before the multiple attack penalty; damage is its stat block's now, a raging badger's extra included.
        def self.in_fight(stats, npc)
          read = ->(kind, name = nil) { (Npcs.stat(npc, kind, name) || {})['total'].to_i }
          raging = Maneuvers.raging?(npc)

          attacks = stats['attacks'].map do |attack|
            strike = Npcs.strike(npc, attack['name'])
            more = raging ? Maneuvers::RAGE_DAMAGE[attack['name']].to_i : 0
            attack.merge('bonus' => strike ? read.call('attack', strike) : attack['bonus'], 'modifier' => attack['modifier'].to_i + more)
          end

          stats.merge('hp' => "#{npc.hp_left} / #{npc.max_hp}",
                      'ac' => read.call('ac'),
                      'perception' => read.call('perception'),
                      'saves' => stats['saves'].keys.to_h { |save| [ save, read.call('save', save) ] },
                      'skills' => stats['skills'].to_h { |skill, info| [ skill, info.merge('value' => read.call('skill', skill)) ] },
                      'attacks' => attacks)
        end

        def self.encounter_section(context)
          npc = context['npc']
          none = t('pf2e.familiar_sheet_none')
          effects = ActiveEffects.on(npc).map { |effect| "#{effect.name} (#{ActiveEffects.remaining(effect)})" }
          rows = [
            [ [ t('pf2e.familiar_sheet_label_id'), "##{npc.number}" ], [ t('pf2e.familiar_sheet_label_actions'), actions_text(npc) ] ],
            [ [ t('pf2e.familiar_sheet_label_conditions'), Pf2e.condition_labels(npc, false).join(', ').presence || none ] ],
            [ [ t('pf2e.familiar_sheet_label_effects'), effects.join(', ').presence || none ] ]
          ]
          if Support.supported?(npc)
            rows << t('pf2e.companion_sheet_supporting', :name => npc.name, :master => context['char'].name)
          end

          section(t('pf2e.familiar_sheet_section_encounter', :id => npc.encounter&.id), rows)
        end

        # `1 of 2 used (Commanded)`, `0 of 1 used (its own action)`, `0 of 0 used (not Commanded)`.
        def self.actions_text(npc)
          state = if Minion.commanded?(npc) then t('pf2e.familiar_sheet_commanded')
                  elsif Minion.turn_actions(npc).positive? then t('pf2e.companion_sheet_own_action')
                  else t('pf2e.familiar_sheet_not_commanded')
                  end

          t('pf2e.familiar_sheet_actions', :used => TurnState.turn(npc)['actions'].to_i, :total => TurnState.actions(npc),
                                           :state => state)
        end

        def self.stat_sections(context)
          [ basic_section(context), attributes_section(context), stats_section(context), saves_section(context),
            skills_section(context), attacks_section(context), gear_section(context), support_section(context), maneuver_section(context),
            specializations_section(context), special_section(context), notes_section(context) ]
        end

        def self.basic_section(context)
          found = context['stats']
          companion = context['companion']

          section(t('pf2e.companion_sheet_section_basic'), [
            [ [ t('pf2e.companion_label_type'), companion['type'] ], [ t('pf2e.companion_label_source'), companion['source'] ] ],
            [ [ t('pf2e.companion_label_level'), found['level'] ], [ t('pf2e.companion_label_stage'), capitalized(found['stage']) ] ],
            [ [ t('pf2e.companion_label_size'), found['size'] ], [ t('pf2e.companion_label_traits'), traits(found['traits']) ] ]
          ])
        end

        def self.attributes_section(context)
          values = context['stats']['attributes']
          cells = ATTRIBUTES.map { |name, short| [ short, Companion.signed(values[name]) ] }

          section(t('pf2e.companion_sheet_section_attributes'), [ cells.first(3), cells.last(3) ])
        end

        # "40 feet, climb 25 feet", or "swim 40 feet" for a companion with no land Speed.
        def self.speeds(found)
          found['speeds'].map do |kind, feet|
            kind == 'land' ? t('pf2e.companion_sheet_feet', :feet => feet) : t('pf2e.companion_sheet_feet_kind', :kind => kind, :feet => feet)
          end.join(', ')
        end

        def self.stats_section(context)
          found = context['stats']
          rows = [ [ [ t('pf2e.companion_label_hp'), found['hp'] ], [ t('pf2e.companion_label_ac'), found['ac'] ] ],
                   [ [ t('pf2e.companion_label_rank_perception'), Companion.signed(found['perception']) ],
                     [ t('pf2e.companion_label_speed'), speeds(found) ] ] ]
          rows << [ [ t('pf2e.companion_label_senses'), found['senses'].join(', ') ] ] unless found['senses'].empty?

          unless found['weaknesses'].empty?
            weak = found['weaknesses'].map { |kind, amount| "#{kind} #{amount}" }.join(', ')
            rows << [ [ t('pf2e.companion_label_weaknesses'), weak ] ]
          end

          section(t('pf2e.companion_sheet_section_stats'), rows)
        end

        def self.saves_section(context)
          saves = context['stats']['saves']

          section(t('pf2e.companion_sheet_section_saves'), [ saves.map { |save, value| [ save, Companion.signed(value) ] } ])
        end

        def self.skills_section(context)
          cells = context['stats']['skills'].map { |skill, info| [ skill, Companion.signed(info['value']) ] }
          rows = cells.each_slice(3).to_a
          rows << t('pf2e.companion_sheet_other_skills', :subject => context['subject'])

          section(t('pf2e.companion_sheet_section_skills'), rows)
        end

        # "Jaws: +15 (Finesse, Magical), 2d8+8 piercing".
        def self.attacks_section(context)
          rows = context['stats']['attacks'].map do |attack|
            shown = attack['traits'].empty? ? '' : " (#{traits(attack['traits'])})"
            "#{attack['name']}: #{Companion.signed(attack['bonus'])}#{shown}, #{Companion.damage(attack)}"
          end

          section(t('pf2e.companion_sheet_section_attacks'), rows)
        end

        # What it wears: its barding, what it has invested (of 2), and anything else staff let it wear.
        def self.gear_section(context)
          worn = Gear.worn(context['char'], context['companion']).map { |item| Gear.facts(item) }
          title = t('pf2e.companion_sheet_section_gear')

          if worn.empty?
            return section(title, [ t('pf2e.companion_sheet_wears_nothing', :subject => context['subject'], :mid => context['mid']) ])
          end

          barding = worn.find { |one| one['armor'] }
          invested = worn.select { |one| one['invested'] }
          other = worn.reject { |one| one['armor'] || one['invested'] }

          rows = []
          rows << [ [ t('pf2e.companion_label_barding'), barding['name'] ] ] if barding
          unless invested.empty?
            label = t('pf2e.companion_sheet_invested', :count => invested.size, :max => Gear::INVEST_LIMIT)
            rows << [ [ label, invested.map { |one| one['name'] }.join(', ') ] ]
          end
          rows << [ [ t('pf2e.companion_sheet_also_wears'), other.map { |one| one['name'] }.join(', ') ] ] unless other.empty?

          section(title, rows)
        end

        def self.support_section(context)
          section(t('pf2e.companion_sheet_section_support'), [ context['stats']['support'].to_s ])
        end

        # Its advanced maneuver once it's nimble or savage; before that, when it learns it.
        def self.maneuver_section(context)
          found = context['stats']
          info = Stats.type_info(context['companion']['type'])['maneuver'] || {}

          unless found['maneuver']
            return section(t('pf2e.companion_sheet_section_maneuver'),
                           [ t('pf2e.companion_sheet_maneuver_later', :subject => context['subject'], :maneuver => info['name']) ])
          end

          section(t('pf2e.companion_sheet_section_maneuver'), [ maneuver_heading(info), info['description'].to_s ])
        end

        # "Takedown (1 action)", "Wing Thrash (2 actions)", "Badger Rage (1 action; Concentrate, Emotion, Mental)".
        def self.maneuver_heading(info)
          actions = info['actions'].to_i == 1 ? t('pf2e.companion_sheet_action') : t('pf2e.companion_sheet_actions', :count => info['actions'])
          parts = [ actions ]
          parts << traits(info['traits']) unless Array(info['traits']).empty?
          parts << info['frequency'] if info['frequency']

          "#{info['name']} (#{parts.join('; ')})"
        end

        def self.specializations_section(context)
          held = context['stats']['specializations']
          return nil if held.empty?

          rows = held.map do |one|
            label = one['choice'] ? "#{one['name']} (#{capitalized(one['choice'])})" : one['name']
            "#{label}: #{one['description']}"
          end

          section(t('pf2e.companion_sheet_section_specializations'), rows)
        end

        def self.special_section(context)
          special = context['stats']['special']
          special.blank? ? nil : section(t('pf2e.companion_sheet_section_special'), [ special ])
        end

        # What binds it, in sentences about it: Command an Animal, the independent action a Mature feat or
        # Imposing Destrier gives, a mount, and the item bonuses it can have.
        def self.notes_section(context)
          subject = context['subject']
          independent = Companion.held(context['char'], :draft => !context['char'].advancing)
                                 .any? { |_name, details| details['companion_independent'].to_i.positive? }

          lines = [ t('pf2e.companion_sheet_note_command', :subject => subject) ]
          lines << t('pf2e.companion_sheet_note_independent', :subject => context['mid']) if independent
          lines << t('pf2e.companion_sheet_note_mount', :subject => subject) if context['stats']['mount']
          lines << t('pf2e.companion_sheet_note_items', :subject => subject)

          section(t('pf2e.companion_sheet_section_notes'), [ lines.join(' ') ])
        end
      end
    end
  end
end
