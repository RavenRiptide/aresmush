require "plugin_test_loader"

module AresMUSH

  # A feat that asks the player something, and the rules beside it that read the answer.
  #
  # Ninety-two of the rules we stock are questions of this sort - a resistance to the kind of damage you
  # chose, a bonus to the performance you named - and a rule reading an answer nobody supplied is worth
  # nothing. Foundry writes the answer as `{item|flags.system.rulesSelections.<flag>}`, and the answer
  # it reads is the choice already recorded with the feat.
  describe "choice sets", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Choice#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char)
      @char.update(:combat => @combat, :pf2_level => 5, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_level_tracker => {}, :pf2_derived => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 12)
      }
      @skills = %w{Acrobatics Performance}.map { |name| Pf2eSkills.create_skill_for_char(name, @char) }
    end

    after(:each) do
      @skills.each(&:delete)
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    # The feat, and the choice recorded with it - which is what `advance/feat` writes.
    def take(feat, bucket, *chosen)
      tracker = { '5' => { 'feat_choices' => { feat => chosen } } }

      @char.update(:pf2_feats => { bucket => [ feat ] },
                   :pf2_level_tracker => chosen.any? ? tracker : {})
    end

    describe "a bonus that applies to the answer" do
      it "should apply when the player is doing the thing they chose" do
        take('Virtuosic Performer', 'skill', 'singing')
        plain = Pf2eSkills.get_skill_bonus(reread, 'Performance')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Performance', [ 'action:perform:singing' ]))
          .to be > plain
      end

      it "should not apply to a performance they did not choose" do
        take('Virtuosic Performer', 'skill', 'singing')
        plain = Pf2eSkills.get_skill_bonus(reread, 'Performance')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Performance', [ 'action:perform:dance' ]))
          .to eq plain
      end

      # Nothing is chosen until the player chooses, and a rule naming an answer nobody gave is ignored
      # rather than applied to everything.
      it "should apply to nothing while no answer is recorded" do
        take('Virtuosic Performer', 'skill')
        plain = Pf2eSkills.get_skill_bonus(reread, 'Performance')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Performance', [ 'action:perform:singing' ]))
          .to eq plain
      end

      it "should count an answer recorded in the player's own spelling" do
        take('Virtuosic Performer', 'skill', 'Singing')
        plain = Pf2eSkills.get_skill_bonus(reread, 'Performance')

        expect(Pf2eSkills.get_skill_bonus(reread, 'Performance', [ 'action:perform:singing' ]))
          .to be > plain
      end

      it "should ask which performance when the feat is taken during a level-up" do
        found = Pf2e.get_feat_details('Virtuosic Performer')
        to_assign = {}
        advancement = {}
        @char.update(:advancing => true, :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' })

        Pf2e::Advancement::FeatGain.apply(@char, found[0], found[1],
          :bucket => 'skill', :to_assign => to_assign, :advancement => advancement)
        @char.update(:pf2_to_assign => to_assign, :pf2_advancement => advancement)

        key, block = Pf2e.validate_feat_choice(reread, 'Virtuosic Performer')

        expect(Pf2e.choice_options(reread, key, block))
          .to eq %w(Acting Comedy Dance Keyboards Oratory Percussion Singing Strings Winds)

        Pf2e.resolve_feat_choice(reread, key, block, Pf2e.match_choice_option(reread, key, block, 'singing'), nil)

        expect(reread.pf2_to_assign['feat_choices']['Virtuosic Performer']).to eq [ 'Singing' ]
      end
    end

    describe "a resistance to the kind of damage chosen" do
      it "should resist the kind the player chose" do
        take('Nephilim Resistance', 'ancestry', 'fire')

        expect(Pf2e::IWR.of(reread)['resistance'].map { |one| one['type'] }).to include 'fire'
      end

      it "should resist nothing else" do
        take('Nephilim Resistance', 'ancestry', 'fire')

        expect(Pf2e::IWR.of(reread)['resistance'].map { |one| one['type'] }).to_not include 'cold'
      end

      it "should resist nothing while no answer is recorded" do
        take('Nephilim Resistance', 'ancestry')

        expect(Pf2e::IWR.of(reread)['resistance']).to eq []
      end

      # An answer the set never offered is not an answer to it: this one is a skill, not a kind of damage.
      it "should ignore an answer the set could not have offered" do
        take('Nephilim Resistance', 'ancestry', 'acrobatics')

        expect(Pf2e::IWR.of(reread)['resistance']).to eq []
      end

      # The question is asked when the feat is taken, and the label the player picks is what the
      # level records.
      it "should ask which kind when the feat is taken during a level-up" do
        found = Pf2e.get_feat_details('Nephilim Resistance')
        to_assign = {}
        advancement = {}
        @char.update(:advancing => true, :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' })

        Pf2e::Advancement::FeatGain.apply(@char, found[0], found[1],
          :bucket => 'ancestry', :to_assign => to_assign, :advancement => advancement)
        @char.update(:pf2_to_assign => to_assign, :pf2_advancement => advancement)

        key, block = Pf2e.validate_feat_choice(reread, 'Nephilim Resistance')

        expect(Pf2e.choice_options(reread, key, block)).to eq %w(Acid Cold Electricity Fire Sonic)

        Pf2e.resolve_feat_choice(reread, key, block, Pf2e.match_choice_option(reread, key, block, 'fire'), nil)

        expect(reread.pf2_to_assign['feat_choices']['Nephilim Resistance']).to eq [ 'Fire' ]
      end

      it "should resist the kind named by the label the level records" do
        take('Nephilim Resistance', 'ancestry', 'Fire')

        expect(Pf2e::IWR.of(reread)['resistance'].map { |one| one['type'] }).to eq [ 'fire' ]
      end
    end

    # An attack that exists only once the player says which one it is.
    describe "an attack granted for the answer" do
      it "should grant the attack the player chose" do
        take('Bestial Manifestation', 'ancestry', 'Claw')

        expect(Pf2eCombat.granted_strikes(reread).map { |one| one['name'] }).to eq [ 'Claw' ]
      end
    end

    # Taking the feat at a level-up, the way advance/feat does, so its choice is staged.
    def gain(feat, bucket)
      found = Pf2e.get_feat_details(feat)
      to_assign = {}
      advancement = {}
      @char.update(:advancing => true, :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' })

      result = Pf2e::Advancement::FeatGain.apply(@char, found[0], found[1],
        :bucket => bucket, :to_assign => to_assign, :advancement => advancement)
      @char.update(:pf2_to_assign => to_assign, :pf2_advancement => advancement)

      result
    end

    def pick(feat, label)
      key, block = Pf2e.validate_feat_choice(reread, feat)

      Pf2e.resolve_feat_choice(reread, key, block, Pf2e.match_choice_option(reread, key, block, label), nil)
    end

    describe "innate spells granted for the answers" do
      it "should stage both spells a two-pick choice grants" do
        gain('Celestial Magic', 'ancestry')
        pick('Celestial Magic', 'Clear Mind')
        pick('Celestial Magic', 'Everlight')

        expect(reread.pf2_advancement['magic_stats']['Celestial Magic']['innate_spell']['name'])
          .to eq [ 'Clear Mind', 'Everlight' ]
      end
    end

    # A feat taken before its choice was in the config holds no answer and never opened the choice, so
    # staff answer it for the player once the config carries it.
    describe "answering the choice on a feat already held" do
      before(:each) do
        allow_any_instance_of(Character).to receive(:is_approved?).and_return(true)
        @char.update(:pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human', 'heritage' => 'Aesa' })
        take('Extraplanar Supplication', 'ancestry')
      end

      after(:each) do
        reread.magic&.delete
      end

      it "should grant the innate spell for the answer" do
        Pf2e.answer_held_feat_choice(reread, 'Extraplanar Supplication', 'bless')

        grants = Pf2emagic::Entries.innate_grants(reread.magic)

        expect(grants.map { |one| [ one['name'], one['level'], one['tradition'] ] }).to eq [ [ 'Bless', 1, 'divine' ] ]
      end

      it "should record the answer with the feat" do
        Pf2e.answer_held_feat_choice(reread, 'Extraplanar Supplication', 'Bane')

        expect(Pf2e.choice_labels_for(reread, 'Extraplanar Supplication')).to eq [ 'Bane' ]
      end

      it "should refuse a second answer" do
        Pf2e.answer_held_feat_choice(reread, 'Extraplanar Supplication', 'Bless')

        expect(Pf2e.answer_held_feat_choice(reread, 'Extraplanar Supplication', 'Bane')).to be_a String
        expect(Pf2emagic::Entries.innate_grants(reread.magic).map { |one| one['name'] }).to eq [ 'Bless' ]
      end

      it "should refuse an answer that is not an option" do
        expect(Pf2e.answer_held_feat_choice(reread, 'Extraplanar Supplication', 'Heal')).to be_a String
        expect(reread.magic).to be_nil
      end

      it "should refuse a character without the feat" do
        @char.update(:pf2_feats => {})

        expect(Pf2e.answer_held_feat_choice(reread, 'Extraplanar Supplication', 'Bless')).to be_a String
      end

      it "should leave a character part-way through a level to answer it there" do
        @char.update(:advancing => true)

        expect(Pf2e.answer_held_feat_choice(reread, 'Extraplanar Supplication', 'Bless')).to be_a String
      end
    end

    # The creature summoned must share the summoner's lineage, so each lineage is offered only its own
    # summoning spell.
    describe "Summon Nephilim Kin's spells by lineage" do
      def offered(lineage)
        @char.update(:pf2_feats => { 'ancestry' => [ lineage, 'Summon Nephilim Kin' ] })
        block = Pf2e.feat_choice_def(Pf2e.get_feat_details('Summon Nephilim Kin')[1])

        Pf2e.choice_options(reread, 'Summon Nephilim Kin', block)
      end

      it "should offer an angelkin only Summon Celestial" do
        expect(offered('Angelkin')).to eq [ 'Summon Celestial' ]
      end

      it "should offer a hellspawn only Summon Fiend" do
        expect(offered('Hellspawn')).to eq [ 'Summon Fiend' ]
      end
    end

    describe "a choice open only to some takers" do
      def holding_instinct(instinct)
        @char.update(:pf2_archetypeinfo => { 'archetype1' => 'Barbarian Archetype', 'archetype_specialty1' => instinct })
      end

      it "should open Instinct Ability's feat for the Fury instinct" do
        holding_instinct('Fury')
        gain('Instinct Ability', 'charclass')

        expect(reread.pf2_to_assign['feat choice']).to include 'Instinct Ability'
      end

      it "should open nothing for another instinct" do
        holding_instinct('Animal')
        gain('Instinct Ability', 'charclass')

        expect(reread.pf2_to_assign['feat choice'] || {}).to_not include 'Instinct Ability'
      end
    end

    describe "a dedication handed over by a choice" do
      it "should offer a dedication the archetype lock would refuse" do
        @abilities.find { |one| one.name == 'Intelligence' }.update(:base_val => 14)
        @char.update(:pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' },
                     :pf2_feats => { 'charclass' => [ 'Rogue Dedication' ] })

        expect(Pf2e.dedication_archetype_ready?(reread)).to be false

        block = Pf2e.feat_choice_def(Pf2e.get_feat_details('Multitalented')[1])

        expect(Pf2e.choice_options(reread, 'Multitalented', block)).to include 'Wizard Dedication'
      end
    end

    describe "a blessing the champion already has" do
      it "should not be offered again by Second Blessing" do
        allow(Pf2e).to receive(:holds_feature?) { |_char, name| name == 'Blessed Shield' }
        block = Pf2e.feat_choice_def(Pf2e.get_feat_details('Second Blessing')[1])

        expect(Pf2e.choice_options(reread, 'Second Blessing', block)).to eq [ 'Blessed Armament', 'Blessed Swiftness' ]
      end
    end

    # A Foundry question nobody here asks is a feat whose rules read an answer that never arrives.
    # Multiclass dedications are asked through the archetype's own config, and a feat granting an open
    # skill asks through the skill pick; anything else asks with a feat choice, or says staff set it up.
    describe "every feat that asks a question" do
      it "should ask it here too" do
        unasked = (Global.read_config('pf2e_feats') || {}).select do |_name, details|
          next false unless details.is_a?(Hash)
          next false unless Array(details['rules']).any? { |row| row.is_a?(Hash) && row['key'] == 'ChoiceSet' }
          next false if details['feat_choice'] || details['staff_request']
          next false if Array(details['feat_type']).include?('Dedication') && Array(details['traits']).include?('multiclass')

          Array((details['grants'] || {})['skill']).none? { |skill| skill.to_s.casecmp?('open') }
        end

        expect(unasked.keys).to eq []
      end
    end

    # The other half: an answer that says where a value is written rather than what it is worth.
    describe "a rank written to the skill chosen" do
      it "should train the skill the player named" do
        take('Skill Training', 'general', 'Acrobatics')
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2eSkills.get_skill_prof(reread, 'Acrobatics')).to eq 'trained'
      end

      it "should train nothing while no answer is recorded" do
        take('Skill Training', 'general')
        Pf2e::Paths.apply_all!(reread)

        expect(Pf2eSkills.get_skill_prof(reread, 'Acrobatics')).to eq 'untrained'
      end
    end
  end
end
