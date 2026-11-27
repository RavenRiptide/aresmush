require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Class feats whose effect is data alone, checked against what the feat's text says it does.
    describe "class feat data" do

      before(:all) do
        @feats = {}

        %w(ancestry class dedication general skill).each do |file|
          @feats.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
        end

        @spells = {}

        Dir.glob("game/config/pf2e_spells_*.yml").each do |file|
          @spells.merge!(YAML.load_file(file)['pf2e_spells'])
        end

        @magic = YAML.load_file("game/config/pf2e_magic.yml")['pf2e_magic']
        @specialty = YAML.load_file("game/config/pf2e_specialty.yml")['pf2e_specialty']
        @deities = YAML.load_file("game/config/pf2e_deities.yml")['pf2e_deities']
      end

      def feat(name)
        @feats.fetch(name)
      end

      def spell(name)
        @spells.fetch(name) { raise "No spell named #{name.inspect}" }
      end

      def traits(name)
        Array(spell(name)['traits'])
      end

      # The spells `Pf2emagic.get_spells_by_name` finds for a term: an exact match, or else every
      # name containing it.
      def spells_named(term)
        exact = @spells.keys.find { |name| name.casecmp?(term) }
        return [ exact ] if exact

        @spells.keys.select { |name| name.downcase.match?(term.downcase) }
      end

      describe "init_magic" do
        # The flag grants the spell whose name is the feat's own, so a feat named anything else
        # grants nothing.
        it "should name exactly one spell for each feat that carries it" do
          @feats.each_pair do |name, details|
            next unless details['init_magic']

            expect(spells_named(name).size).to eq(1), "#{name} matches #{spells_named(name).inspect}"
          end
        end
      end

      describe "feats that grant a focus spell" do
        it "should give each a choice" do
          [
            'Initiate Warden', 'Advanced Warden', 'Masterful Warden',
            'Domain Initiate', 'Advanced Domain', "Advanced Deity's Domain", 'Domain Acumen', 'Domain Fluency',
            'Basic Lesson', 'Greater Lesson', 'Major Lesson', 'Diverse Mystery'
          ].each do |name|
            expect(feat(name)['feat_choice']).to be_a(Hash), name
          end
        end

        it "should choose the subclass spell of the tier each names" do
          {
            'Advanced Bloodline' => 'advanced', 'Greater Bloodline' => 'greater',
            'Advanced Revelation' => 'advanced', 'Greater Revelation' => 'greater'
          }.each_pair do |name, tier|
            expect(feat(name)['feat_choice']).to include('auto' => 'subclass_spell', 'from' => 'subclass_spell', 'tier' => tier), name
          end
        end

        it "should let a warden take each feat more than once, for a different spell each time" do
          { 'Initiate Warden' => 1, 'Advanced Warden' => 2, 'Masterful Warden' => 3 }.each_pair do |name, rank|
            expect(feat(name)['repeatable']).to be(true), name
            expect(feat(name)['feat_choice']['from_spells']).to include('traits' => [ 'ranger', 'focus' ], 'base_level' => rank), name
          end
        end

        # Player Core's three lists, which are exactly the ranger's focus spells at ranks 1 to 3.
        it "should offer the warden spells the book lists" do
          wardens = @spells.select { |_n, s| (%w(ranger focus) - Array(s['traits'])).empty? }

          expect(wardens.select { |_n, s| s['base_level'].to_i == 1 }.keys.sort).to eq [ 'Gravity Weapon', 'Heal Companion', 'Magic Hide' ]
          expect(wardens.select { |_n, s| s['base_level'].to_i == 2 }.keys.sort).to eq [ 'Animal Feature', 'Enlarge Companion', "Hunter's Luck", 'Soothing Mist' ]
          expect(wardens.select { |_n, s| s['base_level'].to_i == 3 }.keys.sort).to eq [ 'Ephemeral Tracking', "Ranger's Bramble" ]
        end

        it "should ask Warden's Focus for a warden spell" do
          expect(feat("Warden's Focus")['prereq']['focus_spell']).to include('Gravity Weapon', 'Heal Companion', 'Magic Hide')
        end

        it "should add Fey Caller's three illusions to the druid's list as primal spells" do
          adapted = feat('Fey Caller')['magic_stats']['adapted_spell']

          expect(adapted.map { |a| a['name'] }).to eq [ 'Illusory Disguise', 'Illusory Object', 'Illusory Scene' ]
          expect(adapted.map { |a| a['tradition'] }.uniq).to eq [ 'primal' ]
          adapted.each { |a| expect(a['base_level']).to eq(spell(a['name'])['base_level'].to_i), a['name'] }
        end
      end

      # A pool holds a point per focus spell that costs one, counted from the spells, so nothing in
      # the data declares points. A declaration would be read by nothing.
      it "should declare no focus points anywhere in the data" do
        found = []

        walk = lambda do |node, path|
          case node
          when Hash
            node.each_pair do |key, value|
              found << "#{path}/#{key}" if key.to_s == 'focus_pool'
              walk.call(value, "#{path}/#{key}")
            end
          when Array
            node.each_with_index { |value, i| walk.call(value, "#{path}[#{i}]") }
          end
        end

        Dir.glob("game/config/pf2e_*.yml").each { |file| walk.call(YAML.load_file(file), File.basename(file)) }

        expect(found).to eq []
      end

      # Player Core p. 178: "You learn your choice of the patron's puppet hex or phase familiar hex."
      it "should give a first-level witch her choice of hex" do
        classes = YAML.load_file("game/config/pf2e_class.yml")['pf2e_class']
        choice = classes['Witch']['chargen']['feat_choice']["Witch's Hex"]

        expect(choice['options'].keys.sort).to eq [ "Patron's Puppet", 'Phase Familiar' ]

        choice['options'].each_pair do |hex, option|
          expect(option['grants']['magic_stats']['focus_spell']).to eq('hex' => [ hex ])
          expect(traits(hex)).to include('focus', 'hex')
          expect(traits(hex)).not_to include('cantrip')
        end
      end

      describe "bloodline and mystery spells" do
        # Each tier is the focus spell tagged for that subclass at the rank the tier starts at.
        {
          'Sorcerer' => [ 'bloodline', { 'advanced' => 3, 'greater' => 5 } ],
          'Oracle' => [ 'mystery', { 'advanced' => 3, 'greater' => 6 } ]
        }.each_pair do |charclass, (tag, ranks)|
          it "should name each #{tag}'s advanced and greater spell" do
            @specialty.fetch(charclass).each_pair do |subclass, info|
              ranks.each_pair do |tier, rank|
                focus = info["#{tier}_focus_spell"]
                expect(focus).to be_a(Hash), "#{subclass} has no #{tier}_focus_spell"

                name = Array(focus.values.first).first

                expect(traits(name)).to include('focus'), name
                expect(spell(name)['base_level'].to_i).to eq(rank), name
                expect(Array(spell(name)[tag])).to include(subclass.downcase), name
              end
            end
          end
        end
      end

      describe "domains" do
        it "should name real spells for each domain" do
          @magic['domains'].each_pair do |domain, info|
            %w(initial advanced).each do |tier|
              expect(@spells).to have_key(info[tier]), "#{domain} #{tier}: #{info[tier].inspect}"
            end
          end
        end

        # Player Core and Divine Mysteries: every initial domain spell is rank 1 and every advanced
        # one rank 4, each an uncommon cleric focus spell.
        it "should keep every domain spell at its rank" do
          @magic['domains'].each_pair do |domain, info|
            expect(spell(info['initial'])['base_level'].to_i).to eq(1), "#{domain}: #{info['initial']}"
            expect(spell(info['advanced'])['base_level'].to_i).to eq(4), "#{domain}: #{info['advanced']}"
            expect(traits(info['initial'])).to include('cleric', 'focus', 'uncommon'), info['initial']
            expect(traits(info['advanced'])).to include('cleric', 'focus', 'uncommon'), info['advanced']
          end
        end

        it "should give each deity only domains the game has" do
          @deities.each_pair do |deity, info|
            (Array(info['domains']) + Array(info['alternate_domains'])).each do |domain|
              expect(@magic['domains']).to have_key(domain), "#{deity}: #{domain}"
            end
          end
        end

        it "should give each mystery Player Core 2's four domains" do
          expected = {
            'Ancestors' => %w(Death Duty Family Soul), 'Battle' => %w(Destruction Might Protection Zeal),
            'Bones' => %w(Death Decay Undeath Vigil), 'Cosmos' => %w(Darkness Moon Nothingness Star),
            'Flames' => %w(Dust Fire Star Sun), 'Life' => %w(Death Healing Pain Soul),
            'Lore' => %w(Knowledge Magic Secrecy Truth), 'Tempest' => %w(Air Cold Lightning Water)
          }

          expect(@specialty['Oracle'].keys.sort).to eq expected.keys.sort

          expected.each_pair do |mystery, domains|
            expect(@specialty['Oracle'][mystery]['domains']).to eq(domains), mystery
            domains.each { |d| expect(@magic['domains']).to have_key(d) }
          end
        end
      end

      describe "lessons" do
        it "should name a hex and a familiar spell that exist for each lesson" do
          @magic['lessons'].each_pair do |tier, lessons|
            lessons.each_pair do |lesson, info|
              expect(traits(info['hex'])).to include('hex', 'focus'), lesson

              Array(info['spell']).each { |name| expect(@spells).to have_key(name), "#{lesson}: #{name}" }
            end
          end
        end
      end

      describe "refocus" do
        def refills
          [
            'Bloodline Focus', 'Bonded Focus', 'Devoted Focus', 'Domain Focus', 'Hex Focus',
            'Inspirational Focus', 'Meditative Focus', 'Primal Focus', "Revelation's Focus", "Warden's Focus"
          ]
        end

        it "should mark each feat that refills the pool" do
          refills.each do |name|
            expect(@feats.fetch(name)['refocus']).to eq('refill'), name
          end
        end

        # A feat marked by mistake would hand a whole pool back on every Refocus.
        it "should mark only feats whose text says the pool refills" do
          @feats.each_pair do |name, details|
            next unless details['refocus']

            expect(details['shortdesc']).to match(/refill your focus pool|regain all your Focus Points/i), name
          end
        end
      end

      describe "composition cantrips" do
        it "should grant each as a composition cantrip" do
          [ 'Dirge of Doom', 'Song of Marching', 'House of Imaginary Walls' ].each do |name|
            expect(feat(name)['init_magic']).to be(true), name
            expect(traits(name)).to include('cantrip', 'composition'), name
          end
        end
      end

      describe "order spells" do
        it "should grant the spells named after their feats" do
          [ 'Primal Summons', 'Impaling Briars' ].each do |name|
            expect(feat(name)['init_magic']).to be(true), name
            expect(traits(name)).to include('focus', 'druid'), name
          end
        end

        it "should grant the spells named otherwise by name" do
          { 'Wind Caller' => 'Stormwind Flight', 'Invoke Disaster' => 'Storm Lord' }.each_pair do |name, granted|
            expect(feat(name)['magic_stats']).to eq('focus_spell' => { 'order' => [ granted ] })
            expect(traits(granted)).to include('focus', 'druid'), granted
          end
        end
      end

      describe "devotion spells" do
        it "should grant the spells named after their feats" do
          [ "Champion's Sacrifice", 'Spectral Advance' ].each do |name|
            expect(feat(name)['init_magic']).to be(true), name
            expect(traits(name)).to include('focus', 'champion'), name
          end
        end
      end

      it "should raise Animal Skin's unarmored defense to expert" do
        expect(feat('Animal Skin')['grants']).to eq('combat_stats' => { 'armor_prof' => { 'unarmored' => 'expert' } })
      end

      it "should train Monastic Weaponry's monk weapons" do
        expect(feat('Monastic Weaponry')['grants']).to eq('combat_stats' => { 'weapon_prof' => { 'monk' => 'trained' } })
      end

      # Neither is the Additional Lore feat, whose Lore rises at 3rd, 7th and 15th level.
      it "should train the Lore each feat names" do
        skills = YAML.load_file("game/config/pf2e_skills.yml")['pf2e_skills']

        { 'Bardic Lore' => 'Bardic Lore', 'Underworld Investigator' => 'Underworld Lore' }.each_pair do |name, lore|
          expect(feat(name)['grants']).to eq('skill' => [ lore ])
          expect(skills).to have_key(lore)
        end
      end

      # A class table sets a rank's slots outright, so a feat adds to them. The rank is a string
      # because the stored slots are keyed by string, and a number would miss them.
      it "should add a 10th-rank slot for each feat whose text gives one" do
        givers = @feats.select { |_name, details| details['shortdesc'].to_s.match?(/additional 10th-rank spell slot/i) }

        expect(givers.keys).to include('Perfect Encore', "Archwizard's Might")

        givers.each_pair do |name, details|
          expect(details['magic_stats']).to eq('spells_per_day' => { '10' => '+1' }), name
        end
      end

      it "should add a repertoire spell of each rank for Deep Lore and Greater Mental Evolution" do
        [ 'Deep Lore', 'Greater Mental Evolution' ].each do |name|
          expect(feat(name)['magic_stats']).to eq('repertoire_each_rank' => 1), name
        end
      end

      describe "prerequisites" do
        def class_feats
          YAML.load_file("game/config/pf2e_feat_class.yml")['pf2e_feats']
        end

        # A name under `feat` or `orfeat` is matched against the feats a character holds, so one
        # that names anything else can never be met.
        it "should name only feats under feat and orfeat" do
          known = @feats.keys.map(&:downcase)

          class_feats.each_pair do |name, details|
            prereq = details['prereq'] || {}

            Array(prereq['feat']).concat(Array(prereq['orfeat'])).each do |wanted|
              expect(known).to include(wanted.to_s.downcase), "#{name} asks for #{wanted.inspect}"
            end
          end
        end

        # Feat names are unique across the feat files, so the Ranger's companion is Animal Companion
        # (Ranger); plain Animal Companion is the Druid's, behind the animal order, and a Ranger
        # feat asking for it could never be taken. Asking for the Ranger's own feat also keeps
        # Druids out, which assoc_charclass does not do once a character is advancing.
        it "should have Ranger companion feats ask for the Ranger's Animal Companion" do
          ranger_chain = [ "Companion's Cry", 'Mature Animal Companion (Ranger)', 'Stealthy Companion', 'Masterful Companion' ]

          class_feats.each_pair do |name, details|
            next unless Array(details['assoc_charclass']).include?('Ranger')

            expect(Array((details['prereq'] || {})['feat'])).not_to include('Animal Companion'), name
          end

          ranger_chain.each do |name|
            expect(class_feats[name]['prereq']['feat']).to include('Animal Companion (Ranger)'), name
          end
        end

        # A feat that wants any animal companion accepts each feat that grants one.
        it "should accept every companion-granting feat where any companion will do" do
          companions = [ 'Animal Companion', 'Animal Companion (Ranger)', 'Faithful Steed' ]

          [ 'Side by Side (Ranger)', 'Fell Rider', 'Ferocious Beasts' ].each do |name|
            expect(feat(name)['prereq']['orfeat']).to include(*companions), name
          end

          expect(feat('Ferocious Beasts')['prereq']['orfeat']).to include('Pet', 'Bonded Animal')
          expect(feat('Ferocious Beasts')['prereq']['feat']).to eq [ 'Oruch Ferocity' ]
        end

        # Every name a `feature` prereq asks for is one a class table grants: a feature, or an
        # option of a class choice. Or an option of a feat's choice, which holds_feature? also
        # matches: Shed Tail asks for the tail Ciith Armaments gave.
        it "should name only features a class or feat choice grants" do
          granted = []

          collect = lambda do |node|
            case node
            when Hash
              node.each_pair do |key, value|
                granted.concat(Array(value).map(&:to_s)) if key.to_s == 'charclass_feature'
                granted.concat(value['options'].keys) if %w(charclass_choice choose).include?(key.to_s) && value.is_a?(Hash) && value['options'].is_a?(Hash)
                collect.call(value)
              end
            when Array
              node.each { |item| collect.call(item) }
            end
          end

          %w(class specialty).each { |file| collect.call(YAML.load_file("game/config/pf2e_#{file}.yml")) }

          @feats.each_value do |details|
            options = (details['feat_choice'] || {})['options'] if details.is_a?(Hash)
            granted.concat(options.keys) if options.is_a?(Hash)
          end

          @feats.each_pair do |name, details|
            Array((details['prereq'] || {})['feature']).each do |wanted|
              expect(granted).to include(wanted), "#{name} asks for the feature #{wanted.inspect}"
            end
          end
        end

        it "should ask for what each feat's text names" do
          {
            'Heal Mount' => { 'level' => 8, 'feat' => [ 'Faithful Steed' ], 'focus_spell' => [ 'Lay on Hands' ] },
            'Rejuvenating Touch' => { 'level' => 18, 'focus_spell' => [ 'Lay on Hands' ] },
            'Discordant Voice' => { 'level' => 18, 'focus_spell' => [ 'Courageous Anthem' ] },
            'Restorative Channel' => { 'level' => 8, 'divine_font' => [ 'heal' ] },
            'Heroic Recovery' => { 'level' => 10, 'divine_font' => [ 'heal' ] },
            'Fast Channel' => { 'level' => 14, 'divine_font' => [ 'heal', 'harm' ] },
            'Perfect Form Control' => { 'level' => 18, 'feat' => [ 'Form Control' ], 'ability' => [ 'Strength/18' ] },
            "Champion's Sacrifice" => { 'level' => 12 },
            'Reflexive Riposte' => { 'level' => 10, 'feature' => [ 'Opportune Riposte' ] },
            'Impossible Riposte' => { 'level' => 14, 'feature' => [ 'Opportune Riposte' ] },
            'Parry and Riposte' => { 'level' => 18, 'feature' => [ 'Opportune Riposte' ] },
            'Radiant Armament' => { 'level' => 10, 'feature' => [ 'Blessed Armament' ] },
            'Armament Paragon' => { 'level' => 20, 'feature' => [ 'Blessed Armament' ] },
            'Shield Paragon' => { 'level' => 20, 'feature' => [ 'Blessed Shield' ] },
            'Spectral Advance' => { 'level' => 10, 'feature' => [ 'Blessed Swiftness' ] },
            'Swift Paragon' => { 'level' => 20, 'feature' => [ 'Blessed Swiftness' ] },
            'Bloodline Perfection' => { 'level' => 20, 'feature' => [ 'Bloodline Paragon' ] },
            'Sanctify Armament' => { 'level' => 8, 'sanctification' => [ 'holy', 'unholy' ] },
            'Aura of Faith' => { 'level' => 12, 'sanctification' => [ 'holy', 'unholy' ] },
            'Aura of Righteousness' => { 'level' => 14, 'sanctification' => [ 'holy' ] },
            'Eternal Blessing' => { 'level' => 16, 'sanctification' => [ 'holy' ] },
            'Eternal Bane' => { 'level' => 16, 'sanctification' => [ 'unholy' ] },
            'Prevailing Position' => { 'level' => 10, 'stances' => 1 },
            'Fuse Stance' => { 'level' => 16, 'stances' => 2 },
            'Interweave Dispel' => { 'level' => 14, 'repertoire_spell' => [ 'Dispel Magic' ] },
            'Enhanced Familiar' => { 'level' => 2, 'familiar' => true }
          }.each_pair do |name, prereq|
            expect(feat(name)['prereq']).to eq(prereq), name
          end
        end

        it "should name each class's own version of a feat that has one per class" do
          {
            'Implausible Purchase (Investigator)' => 'Predictive Purchase (Investigator)',
            'Implausible Purchase (Rogue)' => 'Predictive Purchase (Rogue)',
            'Ricochet Feint' => 'Ricochet Stance (Rogue)',
            'Advanced Efficient Alchemy' => 'Efficient Alchemy (Alchemist)',
            'Mature Animal Companion (Druid)' => 'Animal Companion',
            'Incredible Companion (Druid)' => 'Mature Animal Companion (Druid)',
            'Incredible Companion (Ranger)' => 'Mature Animal Companion (Ranger)'
          }.each_pair do |name, wanted|
            expect(feat(name)['prereq']['feat']).to eq([ wanted ]), name
          end

          expect(feat('Master of Many Styles')['prereq']['orfeat']).to eq [ 'Opening Stance', 'Reflexive Stance' ]
        end

        # Enhanced Familiar asks for a familiar, however the character came by it. Pet only mentions
        # a familiar gained later, which "you gain a familiar" does not match.
        it "should flag every feat whose text gives a familiar, and only those" do
          @feats.each_pair do |name, details|
            gives = details['shortdesc'].to_s.match?(/\byou gain a familiar\b/i)

            expect(details['familiar'] == true).to eq(gives), name
          end
        end
      end

      # Player Core p. 186.
      it "should give Witch's Armaments its three unarmed attacks, one per taking" do
        details = feat("Witch's Armaments")
        attacks = details['feat_choice']['options'].transform_values { |option| option['grants']['attack'] }

        expect(details['repeatable']).to be true
        expect(attacks).to eq(
          'Eldritch Nails' => { 'Nails' => { 'damage' => '1d6', 'damage_type' => 'S', 'group' => 'Brawling',
                                             'traits' => [ 'agile', 'unarmed' ] } },
          'Iron Teeth' => { 'Jaws' => { 'damage' => '1d8', 'damage_type' => 'P', 'group' => 'Brawling',
                                        'traits' => [ 'unarmed' ] } },
          'Living Hair' => { 'Hair' => { 'damage' => '1d4', 'damage_type' => 'B', 'group' => 'Brawling',
                                         'traits' => [ 'agile', 'disarm', 'finesse', 'trip', 'unarmed' ] } }
        )
      end

      # "Choose a weapon group. You gain proficiency with all advanced weapons in that group as if
      # they were martial weapons of their weapon group."
      it "should let Advanced Weapon Training choose a group whose advanced weapons count as martial" do
        expect(feat('Advanced Weapon Training')['feat_choice']).to eq(
          'summary' => 'a weapon group', 'from_weapon_groups' => { 'category' => 'advanced' }, 'as_category' => 'martial'
        )
      end

      describe "spell books" do
        it "should give Esoteric Polymath a book of occult spells that keeps the repertoire" do
          expect(feat('Esoteric Polymath')['spell_book']).to eq(
            'name' => 'Book of Occult Spells', 'tradition' => 'occult', 'supplements' => 'Bard',
            'keeps_repertoire' => true, 'switch' => 'esotericpolymath'
          )
        end

        it "should give Arcane Evolution a list of arcane spells" do
          expect(feat('Arcane Evolution')['spell_book']).to eq(
            'name' => 'Arcane Evolution List', 'tradition' => 'arcane', 'supplements' => 'Sorcerer',
            'switch' => 'arcaneevolution'
          )
        end

        # A player types the feat's name to prepare from its book, and a switch cannot hold a space.
        it "should name each book's switch after its feat" do
          @feats.each_pair do |name, details|
            next unless details['spell_book']

            expect(details['spell_book']['switch']).to eq(name.downcase.gsub(/[^a-z]/, '')), name
          end
        end

        # "You become trained in one skill of your choice."
        it "should give Arcane Evolution a skill of the player's choice" do
          expect(feat('Arcane Evolution')['grants']).to eq('skill' => [ 'open' ])
        end

        # Player Core p. 258: a success is a critical success, and a failure can be tried again
        # after a week or a level.
        it "should give Magical Shorthand its Learn a Spell rules" do
          expect(feat('Magical Shorthand')['learn_spell']).to eq('upgrade_success' => true, 'retry_after_days' => 7)
        end

        # Player Core p. 201.
        it "should give Spellbook Prodigy Magical Shorthand, prerequisites waived, and soften a critical failure" do
          prodigy = feat('Spellbook Prodigy')

          expect(prodigy['assoc_charclass']).to eq [ 'Wizard' ]
          expect(prodigy['prereq']).to eq('level' => 1, 'skill' => 'Arcana/trained')
          expect(prodigy['grants']).to eq('feat' => [ { 'name' => 'Magical Shorthand', 'prereqs' => 'ignore' } ])
          expect(prodigy['learn_spell']).to eq('soften_critical_failure' => true)
        end

        # Player Core p. 230, the Learning a Spell table: rank => [ price in gp, typical DC ].
        it "should price Learn a Spell by rank" do
          expect(@magic['learn_spell']).to eq(
            'cantrip' => [ 2, 15 ], 1 => [ 2, 15 ], 2 => [ 6, 18 ], 3 => [ 16, 20 ], 4 => [ 36, 23 ],
            5 => [ 70, 26 ], 6 => [ 140, 28 ], 7 => [ 300, 31 ], 8 => [ 650, 34 ], 9 => [ 1500, 36 ],
            10 => [ 7000, 41 ]
          )
        end
      end

      it "should give Signature Spell Expansion two signatures of 3rd rank or lower" do
        stats = feat('Signature Spell Expansion')['magic_stats']

        expect(stats).to eq('signature_spells' => { 'up to 3' => 2 })
        expect(Pf2emagic.any_rank_cap(stats['signature_spells'].keys.first)).to eq 3
      end

      it "should give each sense its feat's text names" do
        expect(feat('Defy the Darkness')['grants']).to eq('special' => [ 'Greater Darkvision' ])
        expect(feat('Lifesense')['grants']).to eq('special' => [ 'Lifesense (imprecise) 10 feet' ])
        expect(feat('Soulsight (Bard)')['grants']).to eq('special' => [ 'Spiritsense (imprecise) 60 feet' ])
      end

      it "should give Reactive Striker the Reactive Strike feat, its higher level waived" do
        expect(feat('Reactive Striker')['grants']).to eq('feat' => [ { 'name' => 'Reactive Strike', 'prereqs' => 'ignore' } ])
        expect(feat('Reactive Strike')).to be_a Hash
      end

      it "should let Peerless Warden choose a peerless warden spell, once per taking" do
        details = feat('Peerless Warden')
        pool = details['feat_choice']['from_spells']
        offered = @spells.select do |_name, info|
          info['base_level'].to_i == pool['base_level'] && (pool['traits'] - Array(info['traits'])).empty?
        end

        expect(details['repeatable']).to be true
        expect(pool['focus_type']).to eq 'warden'
        expect(offered.keys).to contain_exactly("Hunter's Vision", 'Terrain Transposition')
      end

      it "should give Cautious Curiosity its two spells in the tradition of the gnome's innate spells" do
        options = feat('Cautious Curiosity')['feat_choice']['options']

        expect(options.keys).to contain_exactly('Arcane', 'Occult')
        options.each_pair do |label, option|
          innate = option['grants']['magic_stats']['innate_spell']

          expect(option['prereq']).to eq('innate_tradition' => [ label.downcase ])
          expect(innate).to include('level' => 2, 'name' => [ 'Disguise Magic', 'Silence' ], 'tradition' => label.downcase)
          innate['name'].each { |name| spell(name) }
        end
      end

      # Otherworldly Magic is the only sildanyar feat that grants an innate spell, and it is arcane.
      it "should give Otherworldly Acumen a 2nd-rank arcane innate spell, after Otherworldly Magic" do
        details = feat('Otherworldly Acumen')

        expect(details['prereq']).to eq('level' => 9, 'feat' => [ 'Otherworldly Magic' ])
        expect(details['magic_stats']['innate_spell']).to include('level' => 2, 'name' => 'open', 'tradition' => 'arcane')
      end

      describe "feats for daily preparation and spell slots" do
        it "should give Eternal Wings a fly Speed equal to the character's Speed, as Divine Wings has" do
          expect(feat('Eternal Wings')['movement']).to eq([ { 'fly' => 'land' } ])
        end

        it "should make every repertoire spell a signature spell for Ultimate Polymath's own class" do
          details = feat('Ultimate Polymath')

          expect(details['all_signature']).to eq(true)
          expect(details['assoc_charclass']).to eq([ 'Bard' ])
        end

        it "should give Grown of Oak oaken resilience at will, one rank below the highest" do
          innate = feat('Grown of Oak')['magic_stats']['innate_spell']

          expect(innate).to include('level' => 'at will', 'below_top' => 1, 'name' => 'Oaken Resilience', 'tradition' => 'primal')
          expect(innate['level'].to_i).to eq(0)
          spell('Oaken Resilience')
        end

        it "should let Studious Capacity, Greater Vital Evolution and Divine Effusion cast past their slots" do
          expect(feat('Studious Capacity')['overflow_casts']).to eq('per_day' => 1, 'not_top' => true)
          expect(feat('Greater Vital Evolution')['overflow_casts']).to eq('per_day' => 2, 'distinct_ranks' => true)
          expect(feat('Divine Effusion')['overflow_casts']).to eq('per_day' => 2, 'distinct_ranks' => true)
        end

        it "should let Greater Physical Evolution cast a battle form once a day" do
          expect(feat('Greater Physical Evolution')['battle_form_casts']).to eq('per_day' => 1)
        end

        it "should let Restorative Channel trade a heal for its four divine healing spells" do
          trade = feat('Restorative Channel')['font_trade']

          expect(trade['from']).to eq 'Heal'
          expect(trade['spells']).to contain_exactly('Cleanse Affliction', 'Clear Mind', 'Sound Body', 'Sure Footing')
          trade['spells'].each { |name| expect(spell(name)['tradition']).to include('divine') }
        end

        it "should give Superior Bond a second drain and Linked Focus a Focus Point" do
          bond = feat('Superior Bond')

          expect(bond['rules']).to include(include('key' => 'ItemAlteration', 'itemType' => 'action', 'property' => 'frequency-max',
                                                   'value' => 2, 'predicate' => [ 'item:slug:drain-bonded-item' ]))
          expect(bond['drain_bonded']).to eq('extra_use_below_top' => 2)
          expect(feat('Linked Focus')['drain_bonded']).to eq('focus_point' => 'curriculum')
        end

        it "should give Vivacious Conduit an exploration action that heals Constitution times half level" do
          actions = YAML.load_file("game/config/pf2e_actions.yml")['pf2e_actions']
          consequences = YAML.load_file("game/config/pf2e_action_consequences.yml")['pf2e_action_consequences']

          expect(actions['Vivacious Conduit']['traits']).to include('exploration', 'healing', 'vitality')
          expect(consequences['vivacious-conduit']['always']).to eq(
            [ { 'on' => 'actor', 'heal' => '@actor.abilities.con.mod*floor(@actor.level/2)' } ])
        end

        it "should let Call of the Wild, Elemental Summons and Rites of Convocation swap in a summon spell" do
          expect(feat('Call of the Wild')['swaps_prepared']).to eq('into' => [ 'Summon Animal', 'Summon Plant or Fungus' ])
          expect(feat('Elemental Summons')['swaps_prepared']).to eq('into' => [ 'Summon Elemental' ])
          expect(feat('Rites of Convocation')['swaps_prepared']).to eq('into' => 'chosen')
          expect(feat('Rites of Convocation')['feat_choice']['from_spells']).to eq('traits' => [ 'summon' ], 'tradition' => 'own')
          %w(Animal Elemental).each { |kind| spell("Summon #{kind}") }
          spell('Summon Plant or Fungus')
        end

        it "should let Ceremonial Knife bind a knife-group weapon each day as a wand of a familiar's spell" do
          expect(feat('Ceremonial Knife')['daily_choice']).to eq(
            'switch' => 'ceremonialknife', 'pick' => 'knife', 'class' => 'Witch', 'items' => { 'weapon_groups' => [ 'knife' ] },
            'max_rank' => { 'level' => 6, 'rank' => 1, 'every' => 2 }, 'lasts' => 'until_changed')
        end

        it "should let Reprepare Spell prepare again a spell of 4th rank or lower" do
          expect(feat('Reprepare Spell')['reprepare']).to eq('max_rank' => 4)
        end

        it "should let Form Retention prepare a battle form 2 ranks higher, lasting 10 minutes" do
          expect(feat('Form Retention')['prepared_slot']).to eq(
            'switch' => 'formretention', 'cast' => 'retained', 'components_below' => 2, 'spells' => 'battle_form',
            'lasts' => { 'unit' => 'minutes', 'value' => 10 })
        end
      end

      describe "feats that grant a class feature or an action" do
        GRANTED_FEATURES = {
          "Monk's Flurry" => { 'archetype_features' => [ 'Flurry of Blows' ] },
          "Swashbuckler's Riposte" => { 'archetype_features' => [ 'Opportune Riposte' ] },
          'Uncanny Dodge' => { 'archetype_features' => [ 'Deny Advantage' ] },
          'Finishing Precision' => { 'archetype_features' => [ 'Precise Strike', 'Basic Finisher' ] },
          "Investigator's Stratagem" => { 'archetype_features' => [ 'Devise a Stratagem' ] },
          'Keen Recollection' => { 'archetype_features' => [ 'Keen Recollection' ] },
          'Verdant Metamorphosis' => { 'charclass_features' => [ 'Verdant Rest' ] }
        }.freeze

        GRANTED_FEATURES.each_pair do |name, granted|
          it "should give #{name} #{granted.values.flatten.join(' and ')}" do
            expect(feat(name)['grants']['feature']).to eq granted
          end
        end

        # A feature an archetype feat grants sits beside the ones its dedication gave; a class feat's beside
        # the class's own.
        it "should file each feat's features where its type says" do
          @feats.each_pair do |name, details|
            granted = (details['grants'] || {})['feature']
            next unless granted

            wanted = Array(details['feat_type']).include?('Archetype') ? 'archetype_features' : 'charclass_features'

            expect(granted.keys).to eq([ wanted ]), "#{name} files its features under #{granted.keys.inspect}"
          end
        end

        it "should keep Keen Recollection's rule on the feature alone" do
          expect(feat('Keen Recollection')['rules']).to be_nil
        end
      end

      it "should have Monk's Flurry set Flurry of Blows' wait by the feat's own words" do
        details = feat("Monk's Flurry")

        expect(details['recharges']).to eq 'Flurry of Blows'
        expect(Recharge.rounds_of('Flurry of Blows', 'text' => details['shortdesc'])).to eq '1d4'
      end

      describe "feats the encounter engine reads" do
        def rule(name, key)
          Array(feat(name)['rules']).select { |row| row['key'] == key }
        end

        it "should make Diehard's death dying 5, by a path the engine writes" do
          row = rule('Diehard', 'ActiveEffectLike').first

          expect(row).to include('mode' => 'upgrade', 'path' => 'system.attributes.dying.max', 'value' => 5)
          expect(Paths.for(row['path'])).not_to be_nil
        end

        it "should give Stone Face 2 more Will DC against Intimidation" do
          row = rule('Stone Face', 'FlatModifier').find { |one| one['selector'] == 'will-dc' }

          expect(row).to include('type' => 'circumstance', 'value' => 2, 'predicate' => [ 'check:statistic:intimidation' ])
        end

        # Foundry names the actions by its own spelling (`orc-ferocity`), and ours by the setting's.
        { 'Incredible Ferocity' => 'Oruch Ferocity', 'Jinx Glutton' => 'Eat Fortune' }.each_pair do |name, action|
          it "should have #{name} count #{action} by the hour" do
            row = rule(name, 'ItemAlteration').first
            actions = YAML.load_file("game/config/pf2e_actions.yml")['pf2e_actions']

            expect(row).to include('itemType' => 'feat', 'property' => 'frequency-per', 'mode' => 'override', 'value' => 'PT1H')
            expect(row['predicate']).to eq [ "item:slug:#{Domains.slug(action)}" ]
            expect(actions).to have_key action
          end
        end

        it "should roll heal and harm with d10s for Healing Hands and Harming Hands" do
          { 'Healing Hands' => 'heal', 'Harming Hands' => 'harm' }.each_pair do |name, spell|
            row = rule(name, 'DamageDice').first

            expect(row).to include('override' => { 'dieSize' => 'd10' }, 'predicate' => [ "item:slug:#{spell}" ])
            expect(Array(row['selector'])).to contain_exactly('spell-damage', 'spell-healing')
          end
        end

        it "should give Communal Healing a note on heal" do
          expect(rule('Communal Healing', 'Note').first['selector']).to eq 'spell-healing'
        end

        it "should give Pilgrim's Token its token, which counts for the tie" do
          gear = YAML.load_file("game/config/pf2e_gear.yml")['pf2e_gear']

          expect(feat("Pilgrim's Token")['bound_item']).to eq('category' => 'gear', 'item' => "Pilgrim's Token")
          expect(gear.fetch("Pilgrim's Token")).to include('made_only' => true, 'price' => 0)
          expect(gear["Pilgrim's Token"]['rules'].first).to include('key' => 'RollOption', 'option' => 'has-pilgrims-token')
        end

        it "should give Rapid Response 10 feet of Speed while switched on" do
          row = rule('Rapid Response', 'FlatModifier').first

          expect(row).to include('selector' => 'speed', 'type' => 'circumstance', 'value' => 10, 'predicate' => [ 'rapid-response' ])
        end

        # Nothing lends an effect's rules to the other creature, so an effect with no row in
        # `Ephemeral::EFFECTS` would be named and never applied.
        it "should name only effects Ephemeral knows what to do with" do
          named = @feats.flat_map do |name, details|
            Array(details['rules']).select { |row| row['key'] == 'EphemeralEffect' }.map { |row| [ name, Ephemeral.effect_of(row) ] }
          end

          expect(named.map(&:first)).to include('Dread Striker', 'Callow May', "Spirits' Interference", 'Elegant Buckler')
          expect(named.reject { |_name, effect| Ephemeral::EFFECTS.key?(effect) }).to eq []
        end

        it "should read a Speed rule as land Speed" do
          expect(Domains.for('speed', nil, nil)).to include 'speed'
          expect(Domains.for('speed', 'fly', nil)).not_to include 'speed'
        end
      end

      it "should have Raging Intimidation hand over its two skill feats once they can be taken" do
        expect(feat('Raging Intimidation')['feats_when_eligible']).to eq [ 'Intimidating Glare', 'Scare to Death' ]
        feat('Intimidating Glare')
        feat('Scare to Death')
      end
    end

    # Ancestry feats the setting renames, which are actions in Foundry's data. The actions catalogue is
    # matched to feats by name, so without an entry under our name `action/use` refuses them.
    describe "renamed ancestry feats in the actions catalogue" do
      before(:all) do
        @actions = YAML.load_file("game/config/pf2e_actions.yml")['pf2e_actions']
      end

      {
        'Bassin Luck' => [ 'free', nil ],
        'Oruch Ferocity' => [ 'reaction', nil ],
        'Oruch Superstition' => [ 'reaction', nil ],
        'Sildanyar Step' => [ 'action', 1 ],
        'Kailli Roll' => [ 'action', 2 ],
        'Quick Stow (Kailli)' => [ 'free', nil ]
      }.each_pair do |name, (type, cost)|
        it "should hold #{name} as a #{type}" do
          entry = @actions.fetch(name)

          expect(entry).to include('from' => 'feat', 'type' => type, 'category' => 'ancestry')
          expect(entry['cost']).to eq cost
        end
      end
    end

    # Feat keys the encounter engine reads by name: how a condition lands, the concealment flat check,
    # the multiple attack penalty, and what fires a feat. Every name a row gives must be one the
    # catalogues hold, or the row does nothing.
    describe "feat keys the encounter engine reads" do
      before(:all) do
        @feats = {}

        %w(ancestry class dedication general skill).each do |file|
          @feats.merge!(YAML.load_file("game/config/pf2e_feat_#{file}.yml")['pf2e_feats'])
        end

        @actions = YAML.load_file("game/config/pf2e_actions.yml")['pf2e_actions']
        @conditions = YAML.load_file("game/config/pf2e_conditions.yml")['pf2e_conditions']
        @effects = YAML.load_file("game/config/pf2e_effects.yml")['pf2e_effects']
                       .merge(YAML.load_file("game/config/pf2e_house_effects.yml")['pf2e_house_effects'])
      end

      def rows(key)
        @feats.select { |_name, info| info.is_a?(Hash) && info[key] }.flat_map { |name, info| Array(info[key]).map { |row| [ name, row ] } }
      end

      {
        'condition_rules' => [ 'Khazadi Doughtiness', 'Aura of Courage', 'Vigorous Health', 'Stubborn Persistence' ],
        'concealment' => [ 'Blind-Fight', 'Supernatural Senses' ],
        'map_counts' => [ 'Furious Focus' ],
        'map_repeats_free' => [ 'Slippery Prey' ],
        'lifts_effect' => [ 'Second Wind' ],
        'triggers' => [ 'Inviolable', 'Disorienting Opening', 'Brilliant Flash', 'Swift Retribution',
                        'Finishing Follow-Through', 'Immortal Techniques' ]
      }.each_pair do |key, names|
        it "should give #{names.join(', ')} a #{key}" do
          expect(rows(key).map(&:first).uniq).to match_array(names)
        end
      end

      it "should name real conditions, each with something to do" do
        rows('condition_rules').each do |name, row|
          expect(@conditions).to have_key(row['condition']), name
          expect(row.keys & %w{eases_by gained_less flat_check}).not_to be_empty, name
        end
      end

      it "should give a concealment row only the kinds of concealment and its own keys" do
        rows('concealment').each do |name, row|
          expect(row.keys - %w{concealed hidden hidden_not_off_guard predicate}).to eq([]), name
        end
      end

      it "should name actions whose Strikes carry a map_counts" do
        rows('map_counts').each do |name, row|
          expect(@actions.fetch(row['action']).dig('strikes', 'map_counts')).not_to be_nil, name
        end
      end

      it "should lift effects that exist" do
        rows('lifts_effect').each do |name, row|
          expect(@actions).to have_key(row['action']), name
          expect(@effects).to have_key(row['effect']), name
          expect(@conditions).to have_key(row['after']), name
        end
      end

      it "should fire on events the engine fires, naming actions, conditions and effects that exist" do
        rows('triggers').each do |name, row|
          expect(FeatTriggers::EVENTS).to have_key(row['event']), name
          Array(row['actions'] || row['action']).each { |action| expect(@actions).to have_key(action), name }
          %w{self_condition target_condition}.each { |key| expect(@conditions).to have_key(row[key]), name if row[key] }
          expect(@effects).to have_key(row['self_effect']), name if row['self_effect']
        end
      end
    end
  end
end
