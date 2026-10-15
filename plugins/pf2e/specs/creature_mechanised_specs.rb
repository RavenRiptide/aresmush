require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What the game will do with each part of a creature an author builds, asked of the same readers the
    # engine runs it with, so the editor's word and the fight agree.
    describe CreatureMechanised do

      def said(block)
        CreatureMechanised.of(block).to_h { |one| [ one['part'], one['runs'] ] }
      end

      def ability(name, text, cost: 2, traits: [])
        { 'name' => name, 'type' => 'action', 'cost' => cost, 'traits' => traits, 'text' => text }
      end

      it "should roll a Strike, and offer what follows a hit where the engine has it" do
        block = { 'strikes' => [ { 'name' => 'Jaws', 'bonus' => 9, 'damage' => [ [ '1d8', 'piercing', nil ] ], 'effects' => [ 'Grab', 'Drag' ] } ] }

        expect(said(block)).to eq('Strike Jaws' => 'rolled', 'Jaws: Grab' => 'offered', 'Jaws: Drag' => 'announced')
      end

      it "should agree with the engine on damage against a basic save" do
        text = 'The hound breathes cold that deals 4d6 cold damage to each creature in a 15-foot cone (DC 20 basic Reflex save).'
        block = { 'actions' => [ ability('Breath', text) ] }

        expect(CreatureAbilities.damage_save(text)).to_not be_nil
        expect(said(block)).to eq('Breath' => 'rolled')
        expect(CreatureMechanised.of(block).first['says']).to include('basic Reflex', 'DC 20', '4d6 cold')
      end

      it "should roll a save whose outcomes leave conditions" do
        text = 'Each creature within 30 feet must attempt a DC 20 Will save.%rFailure The creature is Frightened 1.%rCritical Failure The creature is Frightened 2.'

        expect(said('actions' => [ ability('Howl', text) ])).to eq('Howl' => 'rolled')
      end

      it "should run a venom by its stages" do
        text = 'Saving Throw DC 18 Fortitude; Maximum Duration 6 rounds; Stage 1 1d6 poison damage (1 round); Stage 2 2d6 poison damage (1 round)'
          .gsub('; Stage', '%rStage')

        expect(said('actions' => [ ability('Venom', text, :traits => [ 'poison' ]) ])).to eq('Venom' => 'stages')
      end

      it "should tell the GM when an ability is back, and announce what it cannot read" do
        block = { 'actions' => [ ability('Shriek', "The hound shrieks. It can't use Shriek again for 1d4 rounds."),
                                 ability('Grim Aura', 'Its presence chills the air.', :cost => nil).merge('type' => 'passive') ] }

        expect(said(block)).to eq('Shriek' => 'announced', 'Shriek: its wait' => 'counted', 'Grim Aura' => 'announced')
      end

      it "should heal by regeneration as its turn starts" do
        expect(said('hp_details' => 'regeneration 10 (deactivated by fire)')).to eq('regeneration 10' => 'healed')
      end

      it "should resolve a spell the catalogue knows, and announce one it does not" do
        block = { 'spellcasting' => [ { 'name' => 'Arcane Innate Spells', 'spells' => { '1' => [ 'Force Barrage', 'Made-up Spell' ] } } ] }

        expect(said(block)).to eq('Spell Force Barrage' => 'rolled', 'Spell Made-up Spell' => 'announced')
      end
    end

    describe CreatureVocabulary do
      it "should take the bestiary's traits and the setting's ancestries" do
        expect(CreatureVocabulary.trait?('undead')).to be true
        expect(CreatureVocabulary.trait?('arvek')).to be true
        expect(CreatureVocabulary.trait?('flibbertigibbet')).to be false
      end

      it "should warn of a trait nobody uses and a damage type the engine does not know" do
        block = { 'traits' => [ 'undead', 'flibbertigibbet' ], 'strikes' => [ { 'name' => 'Jaws', 'damage' => [ [ '1d8', 'glitter', nil ] ] } ] }

        expect(CreatureVocabulary.warnings(block).map { |one| one['code'] }).to eq %i{creature_trait_unknown creature_damage_unknown}
      end
    end
  end
end
