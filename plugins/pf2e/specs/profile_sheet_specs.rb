require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # The Pathfinder 2e section of a character's profile: who may see which tab, and that each tab's view
    # says what the in-game sheet says, as plain data.
    describe "the profile's Pathfinder 2e section", :dbtest => true do

      before(:all) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        tag = rand(1000000)
        @witch = Character.create(:name => "Hexa#{tag}")
        @fighter = Character.create(:name => "Brawn#{tag}")
        @viewer = Character.create(:name => "Looker#{tag}")
        client = AutoBuilder::CaptureClient.new

        AutoBuilder.new(@witch).build_level_one('Witch')
        AutoBuilder.new(@fighter).build_level_one('Fighter')

        [ 'familiar/name Smudge', 'familiar/species black cat', 'familiar/form land' ].each do |text|
          PF2FamiliarSetCmd.new(client, Command.new(text), Character[@witch.id]).on_command
        end

        [ @witch, @fighter ].each do |char|
          Roles.add_role(Character[char.id], 'approved')
          Ledger.commit_chargen!(Character[char.id])
        end
        Familiar.approve_with_app!(Character[@witch.id])
      end

      after(:all) do
        [ @witch, @fighter, @viewer ].compact.each { |char| Character[char.id]&.delete }
      end

      before(:each) do
        allow(Website).to receive(:check_login).and_return(nil)
        @witch = Character[@witch.id]
        @fighter = Character[@fighter.id]
        @viewer = Character[@viewer.id]
      end

      def asked(handler, char, viewer = @viewer)
        handler.new.handle(double(:args => { 'id' => char.id }, :enactor => viewer ? Character[viewer.id] : nil))
      end

      # Every hash in a view that carries a kind is a named thing, and has a name.
      def named_things(value, found = [])
        case value
        when Hash
          found << value if value.key?(:kind)
          value.each_value { |inner| named_things(inner, found) }
        when Array
          value.each { |inner| named_things(inner, found) }
        end
        found
      end

      describe "who may see it" do
        it "should refuse a character who isn't approved" do
          allow_any_instance_of(Character).to receive(:is_approved?).and_return(false)

          expect(ProfileSheet.refusal(@witch, @viewer, 'sheet').code).to eq :no_sheet
          expect(ProfileSheet.flags(@witch, @viewer)).to be_nil
        end

        it "should refuse an admin" do
          allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)

          expect(ProfileSheet.refusal(@witch, @viewer, 'sheet').code).to eq :no_sheet
        end

        it "should refuse a character who doesn't exist" do
          expect(ProfileSheet.refusal(nil, @viewer, 'sheet').code).to eq :not_found
        end

        it "should refuse a visitor who isn't logged in unless anonymous viewing is on" do
          allow(ProfileSheet).to receive(:anonymous?).and_return(false)
          expect(ProfileSheet.refusal(@witch, nil, 'sheet').code).to eq :login
          expect(asked(PF2ProfileSheetHandler, @witch, nil)[:error]).to eq t('pf2e.profile_sheet_login')

          allow(ProfileSheet).to receive(:anonymous?).and_return(true)
          expect(ProfileSheet.refusal(@witch, nil, 'sheet')).to be_nil
          expect(asked(PF2ProfileSheetHandler, @witch, nil)[:error]).to be_nil
        end

        it "should refuse the Spells tab of a character who doesn't cast spells" do
          expect(ProfileSheet.refusal(@fighter, @viewer, 'spells').code).to eq :not_caster
          expect(asked(Pf2emagic::PF2ProfileSpellsHandler, @fighter)[:error]).to eq t('pf2e.profile_sheet_no_spells', :name => @fighter.name)
        end

        it "should refuse the Familiar tab of a character without an approved familiar" do
          expect(ProfileSheet.refusal(@fighter, @viewer, 'familiar').code).to eq :no_familiar
        end

        it "should tell the profile which tabs to draw" do
          expect(ProfileSheet.flags(@witch, @viewer)).to eq(sheet: true, combat: true, spells: true, inventory: true, familiar: true)
          expect(ProfileSheet.flags(@fighter, @viewer)).to eq(sheet: true, combat: true, spells: false, inventory: true, familiar: false)
        end

        it "should send the flags with the profile's custom fields" do
          expect(Profile::CustomCharFields.get_fields_for_viewing(@witch, @viewer)[:pf2]).to include(sheet: true, familiar: true)
          allow_any_instance_of(Character).to receive(:is_approved?).and_return(false)
          expect(Profile::CustomCharFields.get_fields_for_viewing(@witch, @viewer)).not_to have_key(:pf2)
        end
      end

      describe "the Sheet tab" do
        before(:each) { @view = asked(PF2ProfileSheetHandler, @witch) }

        it "should give the same figures as the in-game sheet" do
          expect(@view[:defenses][:ac]).to eq Pf2eCombat.calculate_ac(@witch)
          expect(@view[:defenses][:hp]).to eq Pf2eHP.get_max_hp(@witch)
          expect(@view[:defenses][:perception][:value]).to eq Pf2eCombat.get_perception(@witch)
          expect(@view[:defenses][:class_dc][:value]).to eq Pf2eCombat.get_class_dc(@witch)
          @view[:defenses][:saves].each do |save|
            expect(save[:value]).to eq Pf2eCombat.get_save_bonus(@witch, save[:name].downcase)
          end
          @view[:skills].each do |skill|
            expect(skill[:value]).to eq Pf2eSkills.get_skill_bonus(@witch, skill[:name])
          end
        end

        it "should give ranks as words" do
          ranks = @view[:skills].map { |skill| skill[:rank] } + @view[:defenses][:saves].map { |save| save[:rank] }

          expect(ranks).not_to be_empty
          expect(ranks).to all(satisfy { |rank| %w{trained expert master legendary}.include?(rank) })
        end

        it "should mark the class's key attribute" do
          expect(@view[:attributes].find { |one| one[:key] }[:name]).to match(/intelligence/i)
        end

        it "should list the class and its patron" do
          expect(@view[:identity][:charclass]).to eq 'Witch'
          expect(@view[:identity][:subclass_label]).to eq 'Patron'
        end

        it "should send every feat, feature, language and trait as a named thing" do
          things = named_things(@view)

          expect(things.map { |one| one[:kind] }.uniq).to include('feat', 'feature', 'language', 'trait')
          expect(things).to all(satisfy { |one| one[:name].is_a?(String) && !one[:name].empty? })
        end
      end

      describe "the Combat tab" do
        it "should give the armor class and its sum" do
          view = asked(PF2ProfileCombatHandler, @witch)
          sum = view[:ac_breakdown]

          expect(view[:ac]).to eq Pf2eCombat.calculate_ac(@witch)
          expect(sum[:base] + sum[:terms].sum { |term| term[:value] }).to eq sum[:total]
        end

        it "should list the unarmed attacks with their attack bonus" do
          fist = asked(PF2ProfileCombatHandler, @fighter)[:unarmed].find { |one| one[:name] =~ /fist/i }

          expect(fist).not_to be_nil
          expect(fist[:attack]).to be_a(Integer)
          expect(fist[:traits].map { |trait| trait[:name] }).to include('Agile')
        end
      end

      describe "the Spells tab" do
        it "should give the witch's casting, kept in the familiar" do
          witch = asked(Pf2emagic::PF2ProfileSpellsHandler, @witch)[:sources].find { |one| one[:name] == 'Witch' }

          expect(witch[:keeps]).to eq 'familiar'
          expect(witch[:dc]).to eq PF2Magic.get_spell_dc(@witch, 'Witch')
          expect(witch[:ranks].first[:rank]).to eq 0
        end
      end

      describe "the Inventory tab" do
        it "should give their money as the gear screen shows it" do
          expect(asked(Pf2egear::PF2ProfileInventoryHandler, @witch)[:money]).to eq Pf2egear.display_money(@witch.pf2_money.to_i)
        end
      end

      describe "the Familiar tab" do
        before(:each) { @view = asked(PF2ProfileFamiliarHandler, @witch) }

        it "should give the familiar's name, master and stats" do
          expect(@view[:name]).to eq 'Smudge'
          expect(@view[:master]).to eq @witch.name
          expect(@view[:ac]).to be_a(Integer)
          expect(@view[:traits].map { |trait| trait[:name] }).to include('Minion')
        end

        it "should name the master instead of speaking to them" do
          expect(@view[:notes]).to include(@witch.name)
          expect(@view[:notes]).not_to match(/\byou\b/i)
          expect(@view[:spells][:text]).not_to match(/\byou\b/i)
        end
      end

      it "should send no colour codes in any tab" do
        [ [ PF2ProfileSheetHandler, @witch ], [ PF2ProfileCombatHandler, @witch ], [ Pf2emagic::PF2ProfileSpellsHandler, @witch ],
          [ Pf2egear::PF2ProfileInventoryHandler, @witch ], [ PF2ProfileFamiliarHandler, @witch ] ].each do |handler, char|
          expect(asked(handler, char).to_json).not_to match(/%x|%r|%b/)
        end
      end
    end
  end
end
