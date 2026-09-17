require "plugin_test_loader"

module AresMUSH

  # The circumstances a character has switched on.
  #
  # A RollOption rule declares a circumstance rather than a number, and another rule on the same item is
  # predicated on it: a Clandestine Cloak declares `clandestine-cloak` and predicates its own bonuses on
  # it. Two hundred and nineteen rules on what we stock are declarations of this kind.
  #
  # Foundry defaults a toggleable one to off. Here it is on, because an item a character is wearing
  # should do what it says - and the store exists so a player who wants it off can say so.
  describe Pf2e::RollOptions, :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Opt#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char)
      @char.update(:combat => @combat, :pf2_level => 10, :pf2_conditions => {}, :pf2_traits => [],
                   :pf2_base_info => {}, :pf2_feats => {}, :pf2_roll_options => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
      @skill = Pf2eSkills.create(:name => 'Stealth', :character => @char, :prof_level => 'trained')
      @items = []
    end

    after(:each) do
      @items.each(&:delete)
      @skill&.delete
      @abilities.each(&:delete)
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def give(name)
      info = Global.read_config('pf2e_magicitem', name)
      item = Pf2egear.create_item(@char, 'magicitem', name, 1, info)
      item.update(:invested => true)
      @items << item

      reread
    end

    it "should have the declarations the import wrote" do
      rules = Global.read_config('pf2e_magicitem', 'Clandestine Cloak', 'rules')

      expect(rules.map { |row| row['key'] }).to include 'RollOption'
    end

    describe "what a character is offered" do
      it "should offer nothing when they carry nothing that declares one" do
        expect(Pf2e::RollOptions.declared(reread)).to eq []
      end

      it "should offer what an item they are wearing declares" do
        offered = Pf2e::RollOptions.declared(give('Clandestine Cloak'))

        expect(offered.map { |one| one['option'] }).to include 'clandestine-cloak'
      end

      it "should say which item offered it" do
        offered = Pf2e::RollOptions.declared(give('Clandestine Cloak')).first

        expect(offered['source']).to eq 'Clandestine Cloak'
      end

      it "should offer nothing from an item that is not invested" do
        char = give('Clandestine Cloak')
        @items.first.update(:invested => false)

        expect(Pf2e::RollOptions.declared(Character[char.id])).to eq []
      end
    end

    # On by default, which is this game's rule and not Foundry's.
    describe "whether one holds" do
      it "should hold without being asked for" do
        expect(Pf2e::RollOptions.active(give('Clandestine Cloak'))).to include 'clandestine-cloak'
      end

      it "should reach the bonus that is predicated on it" do
        plain = Pf2eSkills.get_skill_bonus(reread, 'Stealth')

        expect(Pf2eSkills.get_skill_bonus(give('Clandestine Cloak'), 'Stealth')).to eq plain + 1
      end
    end

    # The point of the store: a player can turn one off, which they could not before.
    describe "turning one off" do
      it "should stop it holding" do
        char = give('Clandestine Cloak')
        Pf2e::RollOptions.set(char, 'clandestine-cloak', false)

        expect(Pf2e::RollOptions.active(Character[char.id])).to_not include 'clandestine-cloak'
      end

      it "should take the bonus with it" do
        char = give('Clandestine Cloak')
        with = Pf2eSkills.get_skill_bonus(Character[char.id], 'Stealth')

        Pf2e::RollOptions.set(char, 'clandestine-cloak', false)

        expect(Pf2eSkills.get_skill_bonus(Character[char.id], 'Stealth')).to eq with - 1
      end

      # The cloak's penalty goes with its bonus, which is the trade a player is making when they switch
      # it off.
      it "should take the penalty with it too" do
        char = give('Clandestine Cloak')
        Pf2e::RollOptions.set(char, 'clandestine-cloak', false)
        off = Pf2eSkills.get_skill_bonus(Character[char.id], 'Diplomacy')

        Pf2e::RollOptions.set(Character[char.id], 'clandestine-cloak', true)

        expect(Pf2eSkills.get_skill_bonus(Character[char.id], 'Diplomacy')).to eq off - 1
      end

      it "should say the choice was the player's" do
        char = give('Clandestine Cloak')
        Pf2e::RollOptions.set(char, 'clandestine-cloak', false)

        expect(Pf2e::RollOptions.declared(Character[char.id]).first['chosen']).to be true
      end

      it "should hand it back to the item on default" do
        char = give('Clandestine Cloak')
        Pf2e::RollOptions.set(char, 'clandestine-cloak', false)
        Pf2e::RollOptions.clear(Character[char.id], 'clandestine-cloak')

        expect(Pf2e::RollOptions.active(Character[char.id])).to include 'clandestine-cloak'
      end
    end

    describe "naming one" do
      it "should find it however the player capitalises it" do
        char = give('Clandestine Cloak')

        expect(Pf2e::RollOptions.find(char, 'Clandestine-Cloak')['option']).to eq 'clandestine-cloak'
      end

      it "should find it on part of the name" do
        char = give('Clandestine Cloak')

        expect(Pf2e::RollOptions.find(char, 'clandestine')['option']).to eq 'clandestine-cloak'
      end

      it "should find nothing for a name nothing offers" do
        expect(Pf2e::RollOptions.find(reread, 'vibes')).to be_nil
      end
    end

    it "should render what a player is shown" do
      rendered = Pf2e::PF2RollOptionsTemplate.new(Pf2e::RollOptions.declared(give('Clandestine Cloak')))
                                             .render

      expect(rendered).to match(/clandestine-cloak/)
      expect(rendered).to match(/Clandestine Cloak/)
    end
  end
end
