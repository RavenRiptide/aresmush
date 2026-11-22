require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The picture of a familiar or pet that the profile shows: chosen from the character's own files.
    describe "a familiar's picture", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Hexa#{rand(1000000)}")
        @folder = Profile.character_page_folder(@char)
        uploads = AresMUSH.website_uploads_path
        allow(Profile).to receive(:character_page_files) do
          [ File.join(uploads, @folder, 'smudge.jpg'), File.join(uploads, @folder, 'portrait.png') ]
        end
        allow(Familiar).to receive(:main_source).and_return({ 'name' => 'Familiar', 'kind' => 'spellbook', 'feature' => true })
      end

      after(:each) { @char.delete }

      def char
        Character[@char.id]
      end

      it "should choose a picture from the character's files" do
        expect(FamiliarPicture.choose!(char, 'Smudge.jpg').ok?).to be true
        expect(FamiliarPicture.path(char)).to eq "#{@folder}/smudge.jpg"
      end

      it "should refuse a file that isn't in the character's folder" do
        result = FamiliarPicture.choose!(char, '../someone/else.jpg')

        expect(result.code).to eq :not_their_file
        expect(char.pf2_familiar_image).to be_nil
      end

      it "should clear the picture when the choice is blank" do
        FamiliarPicture.choose!(char, 'smudge.jpg')
        FamiliarPicture.choose!(char, '')

        expect(FamiliarPicture.path(char)).to be_nil
      end

      it "should show no picture once its file is gone" do
        FamiliarPicture.choose!(char, 'smudge.jpg')
        allow(Profile).to receive(:character_page_files).and_return([])

        expect(FamiliarPicture.path(char)).to be_nil
      end

      it "should refuse a character without a familiar or pet" do
        allow(Familiar).to receive(:main_source).and_return(nil)

        expect(FamiliarPicture.choose!(char, 'smudge.jpg').code).to eq :no_familiar
        expect(FamiliarPicture.edit_fields(char)).to be_nil
      end

      it "should give the Edit page the picture chosen" do
        FamiliarPicture.choose!(char, 'smudge.jpg')

        expect(FamiliarPicture.edit_fields(char)[:image][:name]).to eq 'smudge.jpg'
      end

      it "should save through the Edit page only when the Familiar tab sent a choice" do
        expect(Profile::CustomCharFields.save_fields_from_profile_edit2(char, char, { 'custom' => {} })).to eq []
        expect(char.pf2_familiar_image).to be_nil

        expect(Profile::CustomCharFields.save_fields_from_profile_edit2(char, char, { 'custom' => { 'pf2_familiar_image' => 'portrait.png' } })).to eq []
        expect(char.pf2_familiar_image).to eq "#{@folder}/portrait.png"

        errors = Profile::CustomCharFields.save_fields_from_profile_edit2(char, char, { 'custom' => { 'pf2_familiar_image' => 'nope.jpg' } })
        expect(errors).to eq [ t('pf2e.familiar_picture_not_found', :file => 'nope.jpg', :name => char.name) ]
      end
    end
  end
end
