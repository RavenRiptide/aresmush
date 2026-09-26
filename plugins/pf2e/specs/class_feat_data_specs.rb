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
    end
  end
end
