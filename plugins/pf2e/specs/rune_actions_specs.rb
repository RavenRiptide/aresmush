require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Property runes that give their wearer an action (`RuneActions`), and the counteract check two of them
    # roll (`Counteract`).
    describe "rune activations" do

      def self.config(name)
        @read ||= {}
        @read[name] ||= YAML.load_file(File.join(AresMUSH.game_path, 'config', "#{name}.yml")).values.first
      end

      let(:actions) { self.class.config('pf2e_actions') }
      let(:runes) { self.class.config('pf2e_runes') }
      let(:effects) { self.class.config('pf2e_effects').merge(self.class.config('pf2e_house_effects')) }

      describe "the table" do
        it "should name only runes in the catalogue" do
          known = runes.keys.map { |name| Domains.slug(name) }
          named = RuneActions::ROWS.values.flat_map { |row| row['runes'].keys }

          expect(named - known).to eq []
        end

        it "should give every activation an entry in the action catalogue" do
          missing = RuneActions::ROWS.keys.reject { |name| actions[name] && actions[name]['for'] == 'equipment' }

          expect(missing).to eq []
        end

        it "should have a row for every rune activation in the catalogue" do
          listed = actions.select { |_name, entry| entry['for'] == 'equipment' && entry['source'] == 'Pathfinder GM Core' }.keys

          expect(listed.sort).to eq RuneActions::ROWS.keys.sort
        end

        it "should put on only effects in the catalogue" do
          named = RuneActions::ROWS.values.flat_map do |row|
            row['runes'].values.map { |grade| grade['effect'] }.compact + (row['choices'] || {}).values
          end

          expect(named.uniq - effects.keys).to eq []
        end

        it "should run every row one way or another" do
          strikes = RuneActions::ROWS.select { |_name, row| row['run'] == 'strike' }.keys

          expect(RuneActions::ROWS.values.map { |row| row['run'] }.uniq - RuneActions::RUNS.keys).to eq [ 'strike' ]
          expect(strikes.reject { |name| actions[name]['strikes'] }).to eq []
          expect(RuneActions::ROWS.values.map { |row| row['trigger'] }.compact - RuneActions::TRIGGERS.keys).to eq []
          expect(RuneActions::ROWS.keys.select { |name| RuneActions::ROWS[name]['run'] == 'answer' } - RuneActions::ANSWERS.keys).to eq []
        end

        it "should list the grades weakest first, so the greater rune is the one that counts" do
          RuneActions::ROWS.each_value do |row|
            greater = row['runes'].keys.select { |slug| slug.start_with?('greater-') }

            expect(row['runes'].keys.last(greater.size)).to eq greater
          end
        end
      end

      describe "a counteract check" do
        it "should reach three ranks above on a critical success, one on a success, and only lower on a failure" do
          expect(Counteract.highest(5, Degree::CRITICAL_SUCCESS)).to eq 8
          expect(Counteract.highest(5, Degree::SUCCESS)).to eq 6
          expect(Counteract.highest(5, Degree::FAILURE)).to eq 4
          expect(Counteract.highest(5, Degree::CRITICAL_FAILURE)).to be_nil
        end

        it "should say whether it ends an effect of a rank" do
          expect(Counteract.ends?(7, Degree::SUCCESS, 8)).to be true
          expect(Counteract.ends?(7, Degree::SUCCESS, 9)).to be false
          expect(Counteract.ends?(7, Degree::CRITICAL_FAILURE, 1)).to be false
        end
      end
    end

    describe "rune activations in an encounter", :dbtest => true do
      include FightBench

      NATURAL_20 = 1.0

      before(:each) do
        bench!(level: 10, hp: 120)
        add('goblin warrior')
        turn_to(@hero.name)
        @client.said.clear
      end

      after(:each) do
        Array(@carried).each(&:delete)
        clear_bench!
      end

      def foe(name = nil)
        Combatants.all(encounter).find { |one| one.label != @hero.name && (name.nil? || one.label.downcase.start_with?(name)) }
      end

      def actions_used
        TurnState.turn(hero)['actions'].to_i
      end

      # Gear of the hero's own with these property runes, worn or wielded, and copied into the encounter.
      def carry(category, name, property)
        char = Character[@hero.id]
        item = Pf2egear.build_item(char, category, name, Global.read_config(Pf2egear::Inventory.config(category), name))
        item.update(:equipped => true, :runes => { 'fundamental' => { 'potency' => 3 }, 'property' => { 'list' => property } })
        (@carried ||= []) << item
        run(PF2EncounterResyncCmd, "e/resync #{@hero.name}")
        @client.said.clear
        item
      end

      describe "armor" do
        it "should put enlarge or shrink on the wearer, as they choose" do
          carry('armor', 'Full Plate', [ 'Size Changing' ])
          used = actions_used

          hero_types('e/act change size/shrink')

          expect(refused).to eq []
          expect(ActiveEffects.active?(hero, 'Spell Effect: Shrink')).to be true
          expect(actions_used).to eq used + 1
        end

        it "should ask which, spending nothing" do
          carry('armor', 'Full Plate', [ 'Size Changing' ])
          used = actions_used

          hero_types('e/act change size')

          expect(refused.join).to include 'enlarge or shrink'
          expect(actions_used).to eq used
        end

        it "should refuse someone without the rune, saying which rune it needs" do
          hero_types('e/act change size/enlarge')

          expect(refused.join).to include 'size changing rune'
        end

        it "should make the wearer invisible, three times a day with a greater rune" do
          carry('armor', 'Studded Leather', [ 'Greater Invisibility' ])

          hero_types('e/act go invisible')

          expect(refused).to eq []
          expect(Pf2e.held_conditions(hero)).to have_key 'Invisible'
          expect(RuneActions.entry(hero, 'Go Invisible', Actions.info('Go Invisible'))['frequency']['max']).to eq 3
        end

        it "should give a fly Speed, without a wait between uses from a greater rune" do
          carry('armor', 'Full Plate', [ 'Greater Winged' ])

          hero_types('e/act take to the skies')

          expect(refused).to eq []
          expect(ActiveEffects.active?(hero, 'Effect: Winged Rune (Greater)')).to be true
          expect(RuneActions.entry(hero, 'Take to the Skies', Actions.info('Take to the Skies'))).to_not have_key 'frequency'
        end

        it "should tell the room the armor looks like clothes" do
          carry('armor', 'Full Plate', [ 'Raiment' ])

          hero_types('e/act costume change')

          expect(refused).to eq []
          expect(heard).to include 'ordinary or fine clothes'
        end

        it "should point e/use at the action" do
          carry('armor', 'Full Plate', [ 'Size Changing' ])

          hero_types('e/use armor=0')

          expect(refused.join).to include 'e/act change size'
        end
      end

      describe "weapons" do
        it "should Strike with the extending weapon, for two actions, at its reach" do
          carry('weapons', 'Maul', [])
          carry('weapons', 'Longsword', [ 'Extending' ])
          used = actions_used

          hero_types("e/act extend=##{foe.number}")

          expect(refused).to eq []
          expect(heard).to include 'reach 60 feet', 'Longsword'
          expect(actions_used).to eq used + 2
          expect(TurnState.turn(hero)['attacks']).to eq 1
        end

        it "should roll a counteract check against the DC given, and say what it ends" do
          carry('weapons', 'Longsword', [ 'Brilliant' ])

          hero_types('e/act shine bright/25/rank 7', FightBench::HIGH)

          expect(refused).to eq []
          expect(heard).to include 'counteract rank 5', 'ends the rank 7 effect'
        end

        it "should ask for the darkness's DC before rolling" do
          carry('weapons', 'Longsword', [ 'Brilliant' ])
          used = actions_used

          hero_types('e/act shine bright')

          expect(refused.join).to include '<DC>'
          expect(actions_used).to eq used
        end
      end

      describe "reactions to the wearer's own Strike" do
        it "should offer Holy Healing after a critical hit on an unholy creature, and heal double its level" do
          add('imp')
          carry('weapons', 'Longsword', [ 'Holy' ])
          Pf2eHP.get_hp_obj(hero).update(:damage => 50)
          before = hero_hp

          hero_types("e/strike longsword=##{foe('imp').number}", NATURAL_20)
          expect(heard).to include 'Holy Healing may follow'

          hero_types('e/act holy healing')

          expect(refused).to eq []
          expect(hero_hp).to eq before + 2 * foe('imp').holder.pf2_level.to_i
        end

        it "should be used once on a Strike" do
          add('imp')
          carry('weapons', 'Longsword', [ 'Holy' ])

          hero_types("e/strike longsword=##{foe('imp').number}", NATURAL_20)
          hero_types('e/act holy healing')
          hero_types('e/act holy healing')

          expect(refused.join).to include 'already used'
        end

        it "should refuse Holy Healing when the Strike wasn't a critical hit" do
          add('imp')
          carry('weapons', 'Longsword', [ 'Holy' ])

          hero_types("e/strike longsword=##{foe('imp').number}", FightBench::LOW)
          hero_types('e/act holy healing')

          expect(refused.join).to include 'Nothing has triggered'
        end

        it "should make a holy creature bleed from an unholy weapon" do
          add('cassisian')
          carry('weapons', 'Longsword', [ 'Unholy' ])

          hero_types("e/strike longsword=##{foe('cassisian').number}", NATURAL_20)
          hero_types('e/act unholy bloodshed')

          expect(refused).to eq []
          expect(PersistentDamage.held(foe('cassisian').holder).map { |one| one['type'] }).to include 'bleed'
        end

        it "should decapitate on a natural 20 and a failed save" do
          carry('weapons', 'Longsword', [ 'Vorpal' ])
          goblin = foe('goblin')

          hero_types("e/strike longsword=##{goblin.number}", NATURAL_20)
          expect(heard).to include 'Snicker-Snack may follow'

          hero_types('e/act snicker-snack', FightBench::LOW)

          expect(refused).to eq []
          expect(heard).to include 'decapitated'
          expect(goblin.holder.class[goblin.holder.id].hp_left.to_i).to be <= 0
        end

        it "should need a natural 20" do
          carry('weapons', 'Longsword', [ 'Vorpal' ])

          hero_types("e/strike longsword=##{foe('goblin').number}", FightBench::HIGH)
          hero_types('e/act snicker-snack', FightBench::LOW)

          expect(refused.join).to include 'Nothing has triggered'
        end
      end

      # The encounter's copy of the hero's weapon, as it is now.
      def wielded(name = nil)
        Pf2egear::Inventory.held(hero, 'weapons').find { |one| name.nil? || one.name == name || one.shape_of == name }
      end

      describe "a shifting weapon" do
        it "should take another one-handed melee weapon's shape, suppressing the runes that can't apply" do
          own = carry('weapons', 'Longsword', [ 'Shifting', 'Vorpal' ])

          hero_types('e/act shift weapon/warhammer')

          expect(refused).to eq []
          weapon = wielded('Longsword')
          expect(weapon.name).to eq 'Warhammer'
          expect(weapon.wp_damage_type).to eq 'B'
          expect(Pf2egear.property_runes(weapon)).to_not include 'vorpal'
          expect(heard).to include 'suppressed', 'Vorpal'
          expect(PF2Weapon[own.id].name).to eq 'Longsword'
        end

        it "should bring a suppressed rune back with a shape it applies to" do
          carry('weapons', 'Longsword', [ 'Shifting', 'Vorpal' ])

          hero_types('e/act shift weapon/warhammer')
          hero_types('e/act shift weapon/longsword')

          expect(Pf2egear.property_runes(wielded('Longsword'))).to include 'vorpal'
        end

        it "should refuse a shape needing other hands, or one that isn't melee" do
          carry('weapons', 'Longsword', [ 'Shifting' ])

          hero_types('e/act shift weapon/greatsword')
          expect(refused.join).to include 'same number of hands'

          hero_types('e/act shift weapon/longbow')
          expect(refused.join).to include 'melee'
        end
      end

      describe "a spell reservoir" do
        before(:each) do
          allow_any_instance_of(PF2EncounterCastCmd).to receive(:spend_the_spell)
            .and_return('spell name' => 'Fear', 'spell level' => '1', 'spell_abil' => 'Charisma', 'prof_level' => 'expert')
        end

        def exploring
          encounter.update(:mode => Exploration::MODE)
        end

        it "should store a spell cast into it while the party explores" do
          carry('weapons', 'Longsword', [ 'Spell Reservoir' ])
          exploring

          hero_types("e/cast fear=#{@hero.name}/reservoir")

          expect(refused).to eq []
          expect(wielded.reservoir).to include('spell' => 'Fear', 'rank' => 1)
          expect(heard).to include 'casts Fear (rank 1) into'
        end

        it "should refuse to store a spell in a fight, or one too high a rank" do
          carry('weapons', 'Longsword', [ 'Spell Reservoir' ])

          hero_types("e/cast fear=#{@hero.name}/reservoir")
          expect(refused.join).to include '1 minute'

          exploring
          hero_types("e/cast fear=#{@hero.name}/reservoir/rank 4")
          expect(refused.join).to include 'rank 3 or lower'
        end

        it "should release the spell through a Strike, emptying the weapon, its save against DC 30" do
          carry('weapons', 'Longsword', [ 'Spell Reservoir' ])
          wielded.update(:reservoir => { 'spell' => 'Fear', 'rank' => 1, 'caster' => 'Someone' })
          used = actions_used

          hero_types("e/act channeled release=##{foe.number}", FightBench::HIGH)

          expect(refused).to eq []
          expect(heard).to include 'Fear', 'DC 30'
          expect(wielded.reservoir).to eq({})
          expect(actions_used).to eq used + 2
          expect(TurnState.turn(hero)['attacks']).to eq 1
        end

        it "should spend the spell on a miss" do
          carry('weapons', 'Longsword', [ 'Spell Reservoir' ])
          wielded.update(:reservoir => { 'spell' => 'Fear', 'rank' => 1, 'caster' => 'Someone' })

          hero_types("e/act channeled release=##{foe.number}", FightBench::LOW)

          expect(heard).to include 'missed'
          expect(wielded.reservoir).to eq({})
        end

        it "should empty harmlessly, and refuse a release with nothing stored" do
          carry('weapons', 'Longsword', [ 'Spell Reservoir' ])
          wielded.update(:reservoir => { 'spell' => 'Fear', 'rank' => 1, 'caster' => 'Someone' })

          hero_types('e/act safe release')
          expect(wielded.reservoir).to eq({})

          hero_types("e/act channeled release=##{foe.number}")
          expect(refused.join).to include 'contains no spell'
        end

        it "should keep what the weapon contains on the character's own weapon when the encounter ends" do
          own = carry('weapons', 'Longsword', [ 'Spell Reservoir' ])
          wielded.update(:reservoir => { 'spell' => 'Fear', 'rank' => 1, 'caster' => 'Someone' })

          SpellReservoir.settle!(hero)

          expect(PF2Weapon[own.id].reservoir).to include('spell' => 'Fear')
        end
      end

      describe "an antimagic rune" do
        before(:each) do
          allow_any_instance_of(PF2EncounterCastCmd).to receive(:spend_the_spell)
            .and_return('spell name' => 'Fear', 'spell level' => '1', 'spell_abil' => 'Charisma', 'prof_level' => 'expert')
          carry('armor', 'Full Plate', [ 'Antimagic' ])
        end

        it "should offer to counteract a spell that lands on the wearer, and undo it" do
          hero_types("e/cast fear=#{@hero.name}", FightBench::LOW)

          expect(Pf2e.held_conditions(hero)).to have_key 'Frightened'
          expect(heard).to include 'Antimagic Armor may follow'

          hero_types('e/act antimagic armor', FightBench::HIGH)

          expect(refused).to eq []
          expect(heard).to include 'counteracted'
          expect(Pf2e.held_conditions(hero)).to_not have_key 'Frightened'
        end

        it "should be too late once something else has hurt them" do
          hero_types("e/cast fear=#{@hero.name}", FightBench::LOW)
          Pf2eHP.get_hp_obj(hero).update(:damage => 7)

          hero_types('e/act antimagic armor', FightBench::HIGH)

          expect(refused.join).to include 'Too much has happened'
        end
      end

      describe "an animated weapon" do
        it "should fly from the hand to fight, and Strike at the end of its owner's turn" do
          carry('weapons', 'Longsword', [ 'Animated' ])
          used = actions_used

          hero_types("e/act set free=##{foe.number}")

          expect(refused).to eq []
          expect(actions_used).to eq used + 2
          expect(wielded.equipped).to be false

          @dice = FightBench::HIGH
          @client.said.clear
          next_turn

          expect(heard).to include 'animated Longsword Strikes', 'keeps fighting'
        end

        it "should fall on a failed flat check, and rest before it can be set free again" do
          carry('weapons', 'Longsword', [ 'Animated' ])

          hero_types("e/act set free=##{foe.number}")
          @dice = FightBench::LOW
          @client.said.clear
          next_turn

          expect(heard).to include 'falls to the ground'

          wielded.update(:equipped => true)
          turn_to(@hero.name)
          hero_types("e/act set free=##{foe.number}")

          expect(refused.join).to include "can't be set free again"
        end
      end
    end
  end
end
