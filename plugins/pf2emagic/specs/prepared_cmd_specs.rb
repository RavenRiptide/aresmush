require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # `prepared` tells someone who casts no spells so, and a caster with nothing prepared that instead.
    describe PF2DisplayPreparedCmd do

      def run(magic, daily = [], slots: {}, args: nil)
        client = double('client')
        enactor = double('enactor', :is_approved? => true, :magic => magic)
        allow(client).to receive(:emit_failure) { |message| @said = message }
        allow(client).to receive(:emit) { |message| @shown = message }
        allow(Pf2e::DailyChoices).to receive(:listing).and_return(daily)
        allow(Entries).to receive(:slots_by_source).with(magic, 'prepared').and_return(slots)
        allow(PF2DisplayPreparedSpellsTemplate).to receive(:new) do |_char, list, _client|
          @listed = list
          double('template', :render => 'prepared spells')
        end

        command = PF2DisplayPreparedCmd.new(client, Command.new(args ? "prepared #{args}" : 'prepared'), enactor)
        command.parse_args
        command.handle
      end

      def cleric(prepared = {})
        double('magic', :tradition => { 'Cleric' => [ 'divine' ] }, :spells_prepared => prepared, :slot_pairs => {},
                        :mastered_spells => {})
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

      # A Cleric keeps no spellbook, so this is the only place they see their slots before filling them.
      it "should show a prepared caster with slots and nothing prepared their slots" do
        run(cleric, slots: { 'Cleric' => { 'cantrip' => 5, '1' => 2 } })

        expect(@said).to be_nil
        expect(@shown).to eq 'prepared spells'
        expect(@listed).to eq({ 'Cleric' => {} })
      end

      it "should show their slots when they specify the class with nothing prepared" do
        run(cleric, slots: { 'Cleric' => { '1' => 2 } }, args: 'cleric')

        expect(@said).to be_nil
        expect(@listed).to eq({ 'Cleric' => {} })
      end

      it "should keep what they have prepared" do
        run(cleric({ 'Cleric' => { '1' => [ 'Heal' ] } }), slots: { 'Cleric' => { '1' => 2 } })

        expect(@listed).to eq({ 'Cleric' => { '1' => [ 'Heal' ] } })
      end
    end
  end
end
