require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # `prepared` tells someone who casts no spells so, and a caster with nothing prepared that instead.
    describe PF2DisplayPreparedCmd do

      def run(magic, daily = [])
        client = double('client')
        enactor = double('enactor', :is_approved? => true, :magic => magic)
        allow(client).to receive(:emit_failure) { |message| @said = message }
        allow(client).to receive(:emit) { |message| @shown = message }
        allow(Pf2e::DailyChoices).to receive(:listing).and_return(daily)

        PF2DisplayPreparedCmd.new(client, Command.new('prepared'), enactor).handle
      end

      # Daily choices a feat has them make are theirs whether or not they cast, and are what they see then.
      it "should show someone who casts nothing their daily choices instead" do
        run(nil, [ 'prepare/longevity (Ancestral Longevity): Athletics' ])

        expect(@said).to be_nil
        expect(@shown).to include 'prepare/longevity'
      end

      it "should tell someone with no magic that they cast no spells" do
        run(nil)

        expect(@said).to eq t('pf2emagic.you_cast_no_spells')
      end

      it "should tell someone who casts nothing that they cast no spells" do
        allow(Entries).to receive(:innate?).and_return(false)
        run(double('magic', :tradition => { 'innate' => {} }, :spells_prepared => {}, :slot_pairs => {},
                            :mastered_spells => {}))

        expect(@said).to eq t('pf2emagic.you_cast_no_spells')
      end

      it "should tell a caster who prepares nothing that they cast from their repertoire" do
        run(double('magic', :tradition => { 'Bard' => [ 'occult' ] }, :spells_prepared => {}, :slot_pairs => {},
                            :mastered_spells => {}))

        expect(@said).to eq t('pf2emagic.prepares_nothing')
      end

      it "should tell a caster with nothing prepared so" do
        run(double('magic', :tradition => { 'Wizard' => [ 'arcane' ] }, :spells_prepared => {}, :slot_pairs => {},
                            :mastered_spells => {}))

        expect(@said).to eq t('pf2emagic.no_prepared_spells')
      end
    end
  end
end
