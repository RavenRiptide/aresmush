require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # How a companion is read from the feats that give and advance it, what each choice offers, and what a
    # level's review says changed. All of it pure: the feats and choices are handed in.
    describe "animal companion feats and choices" do

      before(:all) do
        @catalogue = YAML.load_file('game/config/pf2e_animal_companions.yml')['pf2e_animal_companions']
        @feats = YAML.load_file('game/config/pf2e_feat_class.yml')['pf2e_feats']
        @ancestry = YAML.load_file('game/config/pf2e_feat_ancestry.yml')['pf2e_feats']
        @skill = YAML.load_file('game/config/pf2e_feat_skill.yml')['pf2e_feats']
        @deities = YAML.load_file('game/config/pf2e_deities.yml')['pf2e_deities']
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_animal_companions').and_return(@catalogue)
      end

      def held(*names)
        names.map { |name| [ name, @feats[name] || @ancestry[name] || @skill[name] ] }
      end

      def labels(map)
        ->(name) { Array(map[name]) }
      end

      describe "the config" do
        it "should mark the three feats that give a companion, and only Faithful Steed as mounts only" do
          givers = @feats.select { |_name, info| info['companion'] == true }

          expect(givers.keys.sort).to eq [ 'Animal Companion', 'Animal Companion (Ranger)', 'Faithful Steed' ]
          expect(givers.values.map { |info| info['feat_choice']['from'] }.uniq).to eq [ 'companion_types' ]
          expect(givers.select { |_name, info| info['companion_mount'] }.keys).to eq [ 'Faithful Steed' ]
        end

        it "should stage each advancing feat, with a choice for nimble or savage and for a specialization" do
          staged = @feats.select { |_name, info| info['companion_stage'] }.transform_values { |info| info['companion_stage'] }

          expect(staged).to eq('Mature Animal Companion (Druid)' => 'mature', 'Mature Animal Companion (Ranger)' => 'mature',
                               'Loyal Warhorse' => 'mature', 'Incredible Companion (Druid)' => 'incredible',
                               'Incredible Companion (Ranger)' => 'incredible', 'Imposing Destrier' => 'incredible',
                               'Specialized Companion (Druid)' => 'specialized', 'Specialized Companion (Ranger)' => 'specialized',
                               'Auspicious Mount' => 'specialized')
          expect(@feats['Imposing Destrier']['feat_choice']['options'].keys).to eq %w{Nimble Savage}
          expect(@feats['Auspicious Mount']['feat_choice']['from']).to eq 'companion_specializations'
        end

        it "should give servitors to exactly the deities a holy champion may follow" do
          with = @deities.select { |_name, info| info['servitors'] }

          expect(with.select { |_name, info| info['servitors'] == 'celestial' }.keys.sort).to eq %w{Althea Angoron Daeus Eluna Gilead Navos Tarien}
          expect(with.select { |_name, info| info['servitors'] == 'monitor' }.keys.sort).to eq %w{Animus Ceinara Dana Kor Rada Reos Serriel Vardama}
          expect(with.values.map { |info| Array(info['allowed_sanctifications']) }).to all(include('Holy'))
        end
      end

      describe "reading the companion" do
        it "should find none without a companion feat" do
          expect(Companion.assemble(held('Side by Side (Druid)'), labels({}))).to eq []
        end

        it "should read the type and the Horse's size from the companion feat's choice" do
          found = Companion.assemble(held('Faithful Steed'), labels('Faithful Steed' => 'Horse (Large)')).first

          expect(found.values_at('id', 'source', 'type', 'size', 'mature', 'path')).to eq [ 'faithful-steed', 'Faithful Steed', 'Horse', 'Large', false, nil ]
        end

        it "should leave the type nil until it's chosen" do
          expect(Companion.assemble(held('Animal Companion'), labels({})).first['type']).to be_nil
        end

        it "should read mature, the path and each specialization from the advancing feats" do
          found = Companion.assemble(held('Animal Companion', 'Mature Animal Companion (Druid)', 'Incredible Companion (Druid)',
                                          'Specialized Companion (Druid)'),
                                     labels('Animal Companion' => 'Wolf', 'Incredible Companion (Druid)' => 'Savage',
                                            'Specialized Companion (Druid)' => [ 'Racer (land)', 'Tracker' ])).first

          expect(found.values_at('type', 'mature', 'path')).to eq [ 'Wolf', true, 'savage' ]
          expect(found['specializations']).to eq [ { 'name' => 'Racer', 'choice' => 'land' }, { 'name' => 'Tracker', 'choice' => nil } ]
        end

        it "should take Auspice's servitors from the deity" do
          found = Companion.assemble(held('Faithful Steed', 'Loyal Warhorse', 'Imposing Destrier', 'Auspicious Mount'),
                                     labels('Faithful Steed' => 'Horse (Large)', 'Imposing Destrier' => 'Savage',
                                            'Auspicious Mount' => 'Auspice'),
                                     :servitors => 'celestial').first

          expect(found['specializations']).to eq [ { 'name' => 'Auspice', 'choice' => 'celestial' } ]
        end

        it "should say which stages still wait on their choice" do
          found = Companion.assemble(held('Animal Companion', 'Mature Animal Companion (Druid)', 'Incredible Companion (Druid)'),
                                     labels('Animal Companion' => 'Wolf'), :open => [ 'Incredible Companion (Druid)' ]).first

          expect(found['pending']).to eq [ 'incredible' ]
          expect(found['waiting']).to eq('incredible' => 'Incredible Companion (Druid)')
          expect(found['path']).to be_nil
        end

        it "should merge what other feats give it" do
          grants = Companion.merged_grants(held('Fell Rider', 'Stealthy Companion', 'Rough Rider'))

          expect(grants).to eq('skills' => { 'Intimidation' => 'trained' }, 'raise_with' => { 'Ambusher' => [ 'Stealth' ] },
                               'mount' => [ 'Wolf' ])
        end
      end

      describe "the type choice" do
        it "should offer the common types, the Horse in each size, and no uncommon type without access" do
          offered = Companion.type_labels(@catalogue)

          expect(offered).to include('Wolf', 'Horse (Medium)', 'Horse (Large)')
          expect(offered).not_to include('Horse', 'Riding Drake', 'Arboreal Sapling')
          expect(offered.size).to eq 15
        end

        it "should offer Arboreal Sapling to the leaf order, and never Riding Drake" do
          offered = Companion.type_labels(@catalogue, :allowed => ->(access) { access == { 'specialize' => 'leaf' } })

          expect(offered).to include 'Arboreal Sapling'
          expect(offered).not_to include 'Riding Drake'
        end

        it "should offer a faithful steed only mounts, and a Rough Rider's wolf" do
          expect(Companion.type_labels(@catalogue, :mount_only => true)).to eq [ 'Horse (Medium)', 'Horse (Large)' ]
          expect(Companion.type_labels(@catalogue, :mount_only => true, :mounts => [ 'Wolf' ])).to eq [ 'Horse (Medium)', 'Horse (Large)', 'Wolf' ]
        end
      end

      describe "the specialization choice" do
        it "should offer each usual specialization the companion lacks, and Racer for each Speed it has" do
          offered = Companion.specialization_labels(@catalogue, :held => [ 'Tracker' ], :speeds => [ 'land', 'climb' ],
                                                    :feat => 'Specialized Companion (Druid)')

          expect(offered).to eq [ 'Ambusher', 'Bully', 'Daredevil', 'Racer (land)', 'Wrecker' ]
        end

        it "should offer Auspice through Auspicious Mount only, and only with a deity's servitors" do
          through = ->(feat, servitors) do
            Companion.specialization_labels(@catalogue, :held => [], :speeds => [ 'land' ], :feat => feat, :servitors => servitors)
          end

          expect(through.call('Auspicious Mount', 'celestial')).to include 'Auspice'
          expect(through.call('Auspicious Mount', nil)).not_to include 'Auspice'
          expect(through.call('Specialized Companion (Ranger)', 'celestial')).not_to include 'Auspice'
        end
      end

      describe "one companion" do
        before(:each) do
          @char = double('char')
        end

        def holding(*names)
          allow(Companion).to receive(:held).and_return(held(*names))
        end

        it "should refuse a second companion feat, naming the first" do
          holding('Animal Companion')

          expect(Companion.block_reason(@char, @feats['Faithful Steed'])).to eq 'pf2e.companion_one_only'
        end

        it "should refuse a companion beside Bonded Animal, and Bonded Animal beside a companion" do
          holding('Bonded Animal')
          expect(Companion.block_reason(@char, @feats['Animal Companion (Ranger)'])).to eq 'pf2e.companion_bonded_animal'

          holding('Animal Companion (Ranger)')
          expect(Companion.block_reason(@char, @skill['Bonded Animal'])).to eq 'pf2e.companion_bonded_animal'
        end

        it "should let the first companion and any other feat through" do
          holding('Bonded Animal')
          expect(Companion.block_reason(@char, @feats['Side by Side (Druid)'])).to be_nil

          holding
          expect(Companion.block_reason(@char, @feats['Animal Companion'])).to be_nil
        end
      end

      describe "a level's review" do
        def companion(**fields)
          { 'type' => 'Wolf', 'size' => nil, 'mature' => false, 'path' => nil, 'specializations' => [], 'pending' => [] }
            .merge(fields.transform_keys(&:to_s))
        end

        def at(one, level, **grants)
          Companion::Stats.of(one, :level => level, :grants => grants.transform_keys(&:to_s), :catalogue => @catalogue)
        end

        it "should say nothing when only the level rises" do
          one = companion(:mature => true)

          expect(Companion::Preview.lines(one, one, at(one, 6), at(one, 7))).to eq []
        end

        it "should list what becoming savage changes, giving only the new values and leaving out Hit Points" do
          before = companion(:mature => true)
          after = companion(:mature => true, :path => 'savage')

          expect(Companion::Preview.lines(before, after, at(before, 7), at(after, 8))).to eq [
            [ 'Stage', 'Savage' ],
            [ 'Size', 'Large' ],
            [ 'Attributes', 'Str +5, Dex +5, Con +4, Wis +3' ],
            [ 'Skills', [ [ 'Athletics', 'Expert' ] ] ],
            [ 'Jaws', "2d8+8 Piercing#{t('pf2e.companion_level_magical')}" ],
            [ 'Advanced Maneuver', 'Takedown' ]
          ]
        end

        it "should group saves, and give ranks of their own their own rows" do
          before = companion
          after = companion(:mature => true)
          rows = Companion::Preview.lines(before, after, at(before, 3), at(after, 4))

          expect(rows.first).to eq [ 'Stage', 'Mature' ]
          expect(rows).to include [ 'Perception', 'Expert' ]
          expect(rows.assoc('Saves').last).to eq [ [ 'Fortitude', 'Expert' ], [ 'Reflex', 'Expert' ], [ 'Will', 'Expert' ] ]
        end

        it "should leave the stage out while a nimble or savage choice is still open" do
          before = companion(:mature => true)
          after = companion(:mature => true, :pending => [ 'incredible' ], :waiting => { 'incredible' => 'Incredible Companion (Druid)' })

          expect(Companion::Preview.lines(before, after, at(before, 7), at(after, 8)).assoc('Stage')).to be_nil
        end

        it "should name a new companion, and a specialization" do
          gained = Companion::Preview.lines(nil, companion, nil, at(companion, 1))
          specialized_before = companion(:mature => true, :path => 'savage')
          specialized_after = companion(:mature => true, :path => 'savage', :specializations => [ { 'name' => 'Racer', 'choice' => 'land' } ])
          special = Companion::Preview.lines(specialized_before, specialized_after, at(specialized_before, 13), at(specialized_after, 14))

          expect(gained).to eq [ [ 'Type', 'Wolf (Young)' ] ]
          expect(special.first(2)).to eq [ [ 'Stage', 'Specialized' ], [ 'Specialization', 'Racer (Land)' ] ]
        end
      end

      describe "what other feats give the stats" do
        it "should train a Fell Rider's companion in Intimidation, and raise a stealthy ambusher's Stealth" do
          plain = Companion::Stats.of({ 'type' => 'Horse' }, :level => 9, :catalogue => @catalogue)
          rider = Companion::Stats.of({ 'type' => 'Horse' }, :level => 9, :grants => { 'skills' => { 'Intimidation' => 'trained' } },
                                      :catalogue => @catalogue)
          ambusher = { 'type' => 'Cat', 'mature' => true, 'path' => 'nimble', 'specializations' => [ { 'name' => 'Ambusher' } ] }
          stealthy = Companion::Stats.of(ambusher, :level => 14, :grants => { 'raise_with' => { 'Ambusher' => [ 'Stealth' ] } },
                                         :catalogue => @catalogue)

          expect(plain['skills']).not_to have_key 'Intimidation'
          expect(rider['skills']['Intimidation']['rank']).to eq 'trained'
          expect(stealthy['skills']['Stealth']['rank']).to eq 'legendary'
        end

        it "should make a Rough Rider's wolf a mount" do
          expect(Companion::Stats.of({ 'type' => 'Wolf' }, :level => 1, :grants => { 'mount' => [ 'Wolf' ] }, :catalogue => @catalogue)['mount']).to be true
        end
      end
    end
  end
end
