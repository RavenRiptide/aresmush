require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Daily choices through the real commands: a skill Ancestral Longevity trains, an egalrin's sword
    # practice, and what a rest in an encounter does to each.
    describe "daily choices", :dbtest => true do

      class DailyChoiceClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def logged_in?
          true
        end

        def emit_failure(message)
          @failures << message.to_s
        end

        %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |message| @said << message.to_s } }
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = DailyChoiceClient.new
        @char = Character.create(:name => "Daily#{rand(1000000)}", :pf2_level => 5, :pf2_conditions => {},
                                 :pf2_traits => [], :pf2_faith => {}, :pf2_features => {}, :pf2_level_tracker => {},
                                 :pf2_roll_options => {}, :pf2_derived => {}, :pf2_daily_choices => {},
                                 :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Egalrin' },
                                 :pf2_feats => { 'ancestry' => [ 'Ancestral Longevity', 'Egalrin Weapon Familiarity' ] })
        @combat = Pf2eCombat.create(:character => @char,
                                    :weapon_prof => { 'simple' => 'trained', 'martial' => 'untrained',
                                                      'advanced' => 'untrained', 'unarmed' => 'trained' })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
        @char.update(:combat => @combat, :hp => @hp)
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }
        @skills = [ Pf2eSkills.create(:character => @char, :name => 'Athletics', :prof_level => 'untrained'),
                    Pf2eSkills.create(:character => @char, :name => 'Arcana', :prof_level => 'trained') ]
        @sword = Pf2egear.create_item(@char, 'weapons', 'Katana', 1, Global.read_config('pf2e_weapons', 'Katana'))
        @longsword = Pf2egear.create_item(@char, 'weapons', 'Longsword', 1, Global.read_config('pf2e_weapons', 'Longsword'))

        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        allow(Login).to receive(:emit_ooc_if_logged_in)
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete if @encounter
        char.weapons.each(&:delete)
        (@skills + @abilities + [ @hp, @combat, @char ]).each(&:delete)
      end

      def char
        Character[@char.id]
      end

      def run(cmd_class, text)
        cmd_class.new(@client, Command.new(text), char).on_command
      end

      def handler(text)
        Pf2emagic.get_cmd_handler(@client, Command.new(text), char)
      end

      it "should route a daily choice's switch, and leave the spell switches where they were" do
        expect(handler('prepare/longevity Athletics')).to eq PF2PrepareDailyCmd
        expect(handler('unprepare/swordpractice')).to eq PF2UnprepareDailyCmd
        expect(handler('prepare/splitslot 3=a, b')).to eq Pf2emagic::PF2PrepareSlotFeatCmd
        expect(handler('prepare/esotericpolymath Heal')).to eq Pf2emagic::PF2PrepareFromBookCmd
      end

      describe "a skill it trains" do
        it "should offer only the skills they are untrained in" do
          run(PF2PrepareDailyCmd, 'prepare/longevity')

          expect(@client.said.join).to include 'Athletics'
          expect(@client.said.join).to_not include 'Arcana'
        end

        it "should train them in it for checks, and not for prerequisites" do
          before = Pf2eSkills.get_skill_bonus(char, 'Athletics')

          run(PF2PrepareDailyCmd, 'prepare/longevity athletics')

          expect(@client.failures).to eq []
          expect(Pf2eSkills.rolling_prof(char, 'Athletics')).to eq 'trained'
          expect(Pf2eSkills.get_skill_bonus(char, 'Athletics')).to eq before + char.pf2_level + 2
          expect(Pf2eSkills.get_skill_prof(char, 'Athletics')).to eq 'untrained'
          expect(DraftSheet.of(char).skill_prof('Athletics')).to eq 'untrained'
        end

        it "should hold the pick until a rest, which clears it" do
          run(PF2PrepareDailyCmd, 'prepare/longevity Athletics')
          run(PF2PrepareDailyCmd, 'prepare/longevity Stealth')

          expect(@client.failures).to eq [ t('pf2e.daily_already_picked', :source => 'Ancestral Longevity', :pick => 'Athletics') ]

          DailyChoices.rested!(char)

          expect(Pf2eSkills.rolling_prof(char, 'Athletics')).to eq 'untrained'
          expect(char.pf2_daily_choices).to eq({})
        end

        it "should take a pick back" do
          run(PF2PrepareDailyCmd, 'prepare/longevity Athletics')
          run(PF2UnprepareDailyCmd, 'unprepare/longevity')

          expect(@client.failures).to eq []
          expect(Pf2eSkills.rolling_prof(char, 'Athletics')).to eq 'untrained'
        end

        it "should do nothing for a character without the feat" do
          char.update(:pf2_feats => { 'ancestry' => [] })

          run(PF2PrepareDailyCmd, 'prepare/longevity Athletics')

          expect(@client.failures).to eq [ t('pf2e.daily_not_held', :switch => 'longevity') ]
        end
      end

      describe "sword practice" do
        it "should offer only the swords they carry" do
          Pf2egear.create_item(@char, 'weapons', 'Shortbow', 1, Global.read_config('pf2e_weapons', 'Shortbow'))

          expect(DailyChoices.options(char, DailyChoices.for_switch(char, 'swordpractice'))).to eq %w{Katana Longsword}
        end

        it "should give familiarity with the practiced sword" do
          expect(Pf2eCombat.get_weapon_prof(char, 'Longsword')).to eq 'untrained'

          run(PF2PrepareDailyCmd, 'prepare/swordpractice longsword')

          expect(@client.failures).to eq []
          expect(Pf2eCombat.get_weapon_prof(char, 'Longsword')).to eq 'trained'
          expect(Pf2eCombat.weapon_options('Longsword', nil, char)).to include 'item:daily-choice:swordpractice'
          expect(Pf2eCombat.weapon_options('Katana', nil, char)).to_not include 'item:daily-choice:swordpractice'
        end

        it "should hold through a rest, unlocked, until they practice with another" do
          run(PF2PrepareDailyCmd, 'prepare/swordpractice Longsword')
          DailyChoices.rested!(char)

          expect(char.pf2_daily_choices['swordpractice']).to include('pick' => 'Longsword', 'locked' => false)
          expect(Pf2eCombat.get_weapon_prof(char, 'Longsword')).to eq 'trained'

          run(PF2PrepareDailyCmd, 'prepare/swordpractice Katana')
          run(PF2UnprepareDailyCmd, 'unprepare/swordpractice')

          expect(@client.failures).to eq []
          expect(char.pf2_daily_choices['swordpractice']).to include('pick' => 'Longsword', 'locked' => false)
        end

        it "should end, and say so, when a rest finds the sword gone" do
          run(PF2PrepareDailyCmd, 'prepare/swordpractice Longsword')
          @longsword.delete

          dropped = DailyChoices.rested!(char)

          expect(dropped.map { |one| one['pick'] }).to eq [ 'Longsword' ]
          expect(char.pf2_daily_choices).to eq({})
        end
      end

      describe "a feat for the day" do
        def fighter(level, features)
          char.update(:pf2_level => level, :pf2_feats => {},
                      :pf2_features => { 'charclass_features' => features })
          char
        end

        def pool(switch)
          DailyChoices.options(char, DailyChoices.for_switch(char, switch))
        end

        it "should open Combat Flexibility only to a fighter holding the feature" do
          expect(DailyChoices.for_switch(fighter(8, []), 'flexibility')).to be_nil
          expect(DailyChoices.for_switch(fighter(9, [ 'Combat Flexibility' ]), 'flexibility')['source']).to eq 'Combat Flexibility'
        end

        it "should offer fighter feats of 8th level or lower that they meet the prerequisites for" do
          fighter(9, [ 'Combat Flexibility' ])

          expect(pool('flexibility')).to include('Sudden Charge', 'Incredible Aim')
          expect(pool('flexibility')).to_not include('Dueling Riposte', 'Crashing Slam')
        end

        it "should lend the feat for play, and never for a prerequisite" do
          fighter(9, [ 'Combat Flexibility' ])

          run(PF2PrepareDailyCmd, 'prepare/flexibility Sudden Charge')

          expect(@client.failures).to eq []
          expect(Pf2e.has_feat?(char, 'Sudden Charge')).to be true
          expect(Pf2e.feats_in_play(char)).to include 'Sudden Charge'
          expect(DraftSheet.of(char).feat_names).to_not include 'SUDDEN CHARGE'
        end

        it "should take a feat that asks its own choice with the answer after a colon" do
          fighter(9, [ 'Combat Flexibility' ])
          details = Global.read_config('pf2e_feats', 'Advanced Weapon Training')
          group = Pf2e.choice_options(char, 'Advanced Weapon Training', Pf2e.feat_choice_def(details)).first

          run(PF2PrepareDailyCmd, 'prepare/flexibility Advanced Weapon Training')

          expect(@client.failures.last).to start_with 'Advanced Weapon Training asks for'

          run(PF2PrepareDailyCmd, "prepare/flexibility Advanced Weapon Training: #{group}")

          expect(@client.failures.size).to eq 1
          expect(char.pf2_daily_choices['flexibility']).to include('pick' => 'Advanced Weapon Training', 'choice' => group)

          advanced = Global.read_config('pf2e_weapons').find { |_name, info|
            info['category'].to_s == 'advanced' && info['group'].to_s.casecmp?(group)
          }&.first
          @combat.update(:weapon_prof => @combat.weapon_prof.merge('martial' => 'expert'))

          expect(Pf2eCombat.get_weapon_prof(char, advanced)).to eq 'expert' if advanced
        end

        it "should let Improved Flexibility's feat build on the first" do
          fighter(15, [ 'Combat Flexibility', 'Improved Flexibility' ])

          expect(pool('improvedflexibility')).to_not include 'Incredible Ricochet'

          run(PF2PrepareDailyCmd, 'prepare/flexibility Incredible Aim')

          expect(pool('improvedflexibility')).to include 'Incredible Ricochet'
          expect(pool('improvedflexibility')).to_not include 'Incredible Aim'

          run(PF2PrepareDailyCmd, 'prepare/improvedflexibility Incredible Ricochet')
          run(PF2UnprepareDailyCmd, 'unprepare/flexibility')

          expect(@client.failures).to eq [ t('pf2e.daily_needed', :by => 'Improved Flexibility', :pick => 'Incredible Aim') ]
          expect(Pf2e.has_feat?(char, 'Incredible Ricochet')).to be true
        end

        it "should let the GM open Ultimate Flexibility's picks again, and nobody else's" do
          fighter(20, [ 'Combat Flexibility', 'Improved Flexibility' ])
          char.update(:pf2_feats => { 'charclass' => [ 'Ultimate Flexibility' ] })

          run(PF2PrepareDailyCmd, 'prepare/flexibility Sudden Charge')

          expect(@client.failures).to eq []
          expect(DailyChoices.reopen!(char).state['cleared']).to eq [ 'Sudden Charge' ]
          expect(char.pf2_daily_choices).to eq({})

          run(PF2PrepareDailyCmd, 'prepare/flexibility Double Slice')

          expect(@client.failures).to eq []

          char.update(:pf2_feats => {})

          expect(DailyChoices.reopen!(char).code).to eq :nothing_to_reopen
        end

        it "should give an Experimental Spellshaping wizard a spellshape feat of half their level from 4th" do
          char.update(:pf2_base_info => { 'charclass' => 'Wizard', 'ancestry' => 'Human',
                                          'specialize_info' => 'Experimental Spellshaping' },
                      :pf2_level => 3, :pf2_feats => {})

          expect(DailyChoices.for_switch(char, 'spellshaping')).to be_nil

          char.update(:pf2_level => 4)

          expect(pool('spellshaping')).to include('Reach Spell', 'Conceal Spell')
          expect(pool('spellshaping')).to_not include 'Explosive Arrival'

          char.update(:pf2_base_info => char.pf2_base_info.merge('specialize_info' => 'Spell Blending'))

          expect(DailyChoices.for_switch(char, 'spellshaping')).to be_nil
        end
      end

      describe "blessed armament" do
        def champion(feats = [])
          char.update(:pf2_base_info => { 'charclass' => 'Champion', 'ancestry' => 'Human' }, :pf2_level => 10,
                      :pf2_feats => { 'charclass' => feats },
                      :pf2_features => { 'charclass_features' => [ 'Blessing of the Devoted (Blessed Armament)' ] })
          char
        end

        it "should be open only to a champion with the blessing" do
          char.update(:pf2_base_info => { 'charclass' => 'Champion', 'ancestry' => 'Human' }, :pf2_feats => {},
                      :pf2_features => { 'charclass_features' => [ 'Blessing of the Devoted (Blessed Shield)' ] })

          expect(DailyChoices.for_switch(char, 'armament')).to be_nil
          expect(DailyChoices.for_switch(champion, 'armament')['source']).to eq 'Blessed Armament'
        end

        it "should ask for the weapon and the rune, and offer what each would take" do
          champion

          run(PF2PrepareDailyCmd, 'prepare/armament Longsword')

          expect(@client.failures.last).to include 'Ghost Touch'
          expect(@client.failures.last).to_not include 'Astral'
        end

        it "should give the weapon its rune for the day, as the effect's own rules" do
          champion

          run(PF2PrepareDailyCmd, 'prepare/armament longsword: ghost touch')

          expect(@client.failures).to eq []
          expect(char.pf2_daily_choices['armament']['pick']).to eq 'Longsword: Ghost Touch'

          source = DailyChoices.sources(char).first
          selections = source['item']['flags']['system']['rulesSelections']

          expect(selections).to eq('weapon' => @longsword.id.to_s, 'rune' => 'ghost-touch')
          expect(Effects.sources(char).map { |one| one['name'] }).to include 'Effect: Blessed Armament'

          longsword = char.weapons.to_a.find { |one| one.name == 'Longsword' }
          katana = char.weapons.to_a.find { |one| one.name == 'Katana' }

          expect(Pf2eCombat.attack_descriptor(char, longsword)['runes']).to include 'ghost-touch'
          expect(Pf2eCombat.attack_descriptor(char, katana)['runes']).to_not include 'ghost-touch'
        end

        it "should add Radiant Armament's runes, and let the GM open the pick again" do
          champion([ 'Radiant Armament' ])

          run(PF2PrepareDailyCmd, 'prepare/armament Longsword: Astral')

          expect(@client.failures).to eq []
          expect(DailyChoices.reopen!(char).state['switches']).to eq [ 'armament' ]
          expect(char.pf2_daily_choices).to eq({})
        end
      end

      it "should give void healing to an oracle who nudges the scales towards death" do
        char.update(:pf2_feats => { 'charclass' => [ 'Nudge the Scales' ] })

        expect(Effects.void_healing?(Effects.facts(char))).to be false

        run(PF2PrepareDailyCmd, 'prepare/scales death')

        expect(@client.failures).to eq []
        expect(Effects.void_healing?(Effects.facts(char))).to be true

        DailyChoices.rested!(char)

        expect(Effects.void_healing?(Effects.facts(char))).to be false
      end

      it "should give a witch's anointed staff a fly Speed for the day" do
        char.update(:pf2_feats => { 'charclass' => [ "Witch's Broom" ] })
        Pf2egear.create_item(@char, 'weapons', 'Staff', 1, Global.read_config('pf2e_weapons', 'Staff'))

        expect(DailyChoices.options(char, DailyChoices.for_switch(char, 'broom'))).to eq [ 'Staff' ]

        run(PF2PrepareDailyCmd, 'prepare/broom staff')

        expect(@client.failures).to eq []
        expect(Movement.entries_for(char)).to include('source' => "Witch's Broom (Staff)", 'fly' => 20)
      end

      it "should open the choices when the GM rests them in an encounter" do
        run(PF2PrepareDailyCmd, 'prepare/longevity Athletics')
        run(PF2PrepareDailyCmd, 'prepare/swordpractice Longsword')

        @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1, :is_active => true)
        Combatants.join(@encounter, @char.name, 10, :holder => char)
        Pf2e.rest(CombatantStates.of(PF2Encounter[@encounter.id], char))

        expect(char.pf2_daily_choices.keys).to eq [ 'swordpractice' ]
        expect(char.pf2_daily_choices['swordpractice']['locked']).to be false
      end

      it "should list the day's choices with prepared, for someone who casts nothing" do
        run(PF2PrepareDailyCmd, 'prepare/longevity Athletics')
        run(Pf2emagic::PF2DisplayPreparedCmd, 'prepared')

        expect(@client.failures).to eq []
        expect(@client.said.last).to include 'prepare/longevity'
        expect(@client.said.last).to include 'Athletics'
        expect(@client.said.last).to include 'prepare/swordpractice'
      end

      describe "the data" do
        def blocks
          DailyChoices.declared
        end

        it "should give every pick what its kind needs, and name only switches that exist" do
          switches = blocks.map { |_name, block| block['switch'].to_s.downcase }
          needs = { 'feat' => 'from_feats', 'effect' => 'effect', 'listed' => 'choices', 'item' => 'items' }

          strays = blocks.flat_map do |name, block|
            missing = Array(block['also_counts']).map { |one| one.to_s.downcase }.reject { |one| switches.include?(one) }
            need = needs[block['pick'].to_s]
            lacking = need && block[need].nil? ? [ "no #{need}" ] : []
            unknown = block['pick'].to_s == 'effect' && ActiveEffects.info(block['effect'].to_s).empty? ? [ 'no such effect' ] : []

            (missing + lacking + unknown).map { |one| "#{name}: #{one}" }
          end

          reprepared = Global.read_config('pf2e_feats').flat_map do |name, info|
            next [] unless info.is_a?(Hash)

            Array(info['daily_reprepare']).map { |one| one.to_s.downcase }.reject { |one| switches.include?(one) }
                                        .map { |one| "#{name}: reprepares #{one}" }
          end

          expect(strays + reprepared).to eq []
        end

        it "should declare only kinds of pick and lengths the game knows" do
          strays = blocks.reject do |_name, block|
            DailyChoices::KINDS.key?(block['pick'].to_s) && DailyChoices::LASTS.include?(block['lasts'].to_s) &&
              !block['switch'].to_s.empty?
          end

          expect(strays.map(&:first)).to eq []
        end

        # A switch on `prepare` reaches one feat's preparations, whichever kind declares it.
        it "should give no two feats the same prepare switch" do
          switches = Global.read_config('pf2e_feats').values.select { |info| info.is_a?(Hash) }.flat_map do |info|
            info.values.select { |value| value.is_a?(Hash) && value['switch'] }.map { |value| value['switch'].to_s.downcase }
          end
          # A class's blocks are a list, which the sweep above does not reach.
          switches += Global.read_config('pf2e_class').values.flat_map { |info| DailyChoices.blocks_of(info) }
                                                     .map { |block| block['switch'].to_s.downcase }

          expect(switches.group_by(&:itself).select { |_switch, all| all.size > 1 }.keys).to eq []
        end
      end
    end
  end
end
