module AresMUSH
  module Pf2e
    module Companion

      # The Animal Companion tab of a character's profile, as plain data: an approved companion's stats and what it
      # wears, from the same reads as `sheet/companion`, on the sheet as it stands outside any level being drafted.
      # Anyone may open a profile, so its sentences name the companion and its master instead of speaking to the
      # master.
      module ProfileView

        def self.of(char)
          companion = Companion.list(char, :draft => false).first
          approved = companion ? Companion.approved_record(char, companion) : nil
          stats = approved ? Companion.stats(char, companion, :draft => false) : nil
          return nil unless stats

          name = approved['name']
          speeds = stats['speeds'] || {}

          { name: name, master: char.name, image: Picture.path(char),
            dead: Companion.dead?(char, companion),
            type: companion['type'], source: companion['source'], stage: SheetView.capitalized(stats['stage']),
            level: stats['level'].to_i, size: stats['size'],
            traits: ProfileSheet.items(Array(stats['traits']).map { |trait| SheetView.capitalized(trait) }, 'trait'),
            hp: stats['hp'].to_i, ac: stats['ac'].to_i, perception: stats['perception'].to_i,
            saves: stats['saves'].map { |save, value| { name: save, value: value.to_i } },
            attributes: SheetView::ATTRIBUTES.map { |attribute, short| { name: short, value: stats['attributes'][attribute].to_i } },
            speed: speeds['land'] ? speeds['land'].to_i : nil,
            special_movement: speeds.except('land').map { |movement, feet| { movement: movement, feet: feet.to_i } },
            senses: Array(stats['senses']),
            weaknesses: (stats['weaknesses'] || {}).map { |kind, amount| "#{kind} #{amount}" },
            skills: stats['skills'].map { |skill, held| { name: skill, value: held['value'].to_i, rank: held['rank'] } },
            attacks: stats['attacks'].map { |attack| attack_of(attack, stats) },
            gear: gear(char, companion),
            support: html(stats['support']),
            maneuver: maneuver(companion, stats),
            specializations: Array(stats['specializations']).map { |one| specialization(one) },
            special: stats['special'].presence,
            notes: notes(char, name, stats) }
        end

        # "Jaws", +6 at trained, "1d8+2 piercing", with its traits.
        def self.attack_of(attack, stats)
          { name: attack['name'], attack: attack['bonus'].to_i, rank: (stats['ranks'] || {})['attack'],
            damage: Companion.damage(attack),
            traits: ProfileSheet.items(Array(attack['traits']).map { |trait| SheetView.capitalized(trait) }, 'trait') }
        end

        # Its barding, what it has invested (of 2), and anything else it wears.
        def self.gear(char, companion)
          worn = Gear.worn(char, companion).map { |item| Gear.facts(item) }
          barding = worn.find { |one| one['armor'] }
          invested = worn.select { |one| one['invested'] }

          { barding: barding ? ProfileSheet.item(barding['name'], 'item') : nil,
            invested: invested.map { |one| ProfileSheet.item(one['name'], 'item') },
            invest_limit: Gear::INVEST_LIMIT,
            other: (worn - [ barding ].compact - invested).map { |one| ProfileSheet.item(one['name'], 'item') } }
        end

        # Its advanced maneuver once it's nimble or savage, or which one it learns then.
        def self.maneuver(companion, stats)
          info = Stats.type_info(companion['type'])['maneuver'] || {}
          return { later: info['name'] } unless stats['maneuver']

          { name: SheetView.maneuver_heading(info), description: html(info['description']) }
        end

        def self.specialization(one)
          label = one['choice'] ? "#{one['name']} (#{SheetView.capitalized(one['choice'])})" : one['name']
          { name: label, description: html(one['description']) }
        end

        # Config text as the portal shows it: its MUSH codes (%r, %t) and markdown (**Requirements**) as HTML.
        def self.html(text)
          Website.format_markdown_for_html(text.to_s).to_s
        end

        # What binds it, in sentences that name it and its master.
        def self.notes(char, name, stats)
          independent = Companion.held(char, :draft => false).any? { |_feat, details| details['companion_independent'].to_i.positive? }

          lines = [ t('pf2e.profile_companion_note_command', :name => name, :char => char.name) ]
          lines << t('pf2e.profile_companion_note_independent', :name => name, :char => char.name) if independent
          lines << t('pf2e.profile_companion_note_mount', :name => name) if stats['mount']
          lines << t('pf2e.profile_companion_note_items', :name => name)
          lines.join(' ')
        end
      end

      # The picture of a character's animal companion that their profile shows. The player chooses it on the
      # portal's Edit page from the files in their character's folder, as they choose a familiar's, and it needs no
      # staff approval. It belongs to the animal, on its record, so a replacement starts with none.
      module Picture

        # Anyone with a companion may choose one, before approval as well as after: the profile shows it once the
        # companion is approved.
        def self.allowed?(char)
          !Companion.main(char).nil?
        end

        # The chosen picture's path, or nil when there is none or its file is no longer in their folder.
        def self.path(char)
          chosen = Companion.entry(char, Companion.main(char))['image'].to_s
          return nil if chosen.empty?

          FamiliarPicture.files(char).include?(chosen) ? chosen : nil
        end

        # What the Edit page needs: what the companion is called, and the picture chosen.
        def self.edit_fields(char)
          return nil unless allowed?(char)

          chosen = path(char)
          { name: Companion.name_of(char), image: chosen ? Website.get_file_info(chosen) : nil }
        end

        # Chooses the picture by its file name in their folder, or clears it when the name is blank.
        def self.choose!(char, name)
          name = name.to_s.strip
          companion = Companion.main(char)
          return Err.new(:no_companion, 'pf2e.companion_picture_no_companion') unless companion

          held = Companion.entry(char, companion)

          if name.empty?
            held.delete('image')
            Companion.save_entry!(char, companion, held)
            return Ok.new(:state => nil)
          end

          wanted = File.join(Profile.character_page_folder(char), name.downcase)
          found = FamiliarPicture.files(char).find { |file| file.casecmp?(wanted) }
          return Err.new(:not_their_file, 'pf2e.companion_picture_not_found', 'file' => name, 'name' => char.name) unless found

          Companion.save_entry!(char, companion, held.merge('image' => found))
          Ok.new(:state => found)
        end
      end
    end
  end
end
