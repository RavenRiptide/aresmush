require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Who casts: anyone with a tradition beyond innate, or innate spells of their own.
    describe "is_caster?" do

      def char(tradition)
        double('char', :magic => double('magic', :tradition => tradition))
      end

      it "should count a tradition beyond innate" do
        expect(Pf2emagic.is_caster?(char('Wizard' => [ 'arcane' ], 'innate' => {}))).to be true
      end

      it "should count innate alone only where it holds spells" do
        allow(Entries).to receive(:innate?).and_return(false, true)

        expect(Pf2emagic.is_caster?(char('innate' => {}))).to be false
        expect(Pf2emagic.is_caster?(char('innate' => {}))).to be true
      end

      it "should leave the character's traditions as they were" do
        tradition = { 'Wizard' => [ 'arcane' ], 'innate' => {} }

        Pf2emagic.is_caster?(char(tradition))

        expect(tradition.keys).to eq [ 'Wizard', 'innate' ]
      end

      it "should not be a caster with no magic at all" do
        expect(Pf2emagic.is_caster?(double('char', :magic => nil))).to be false
      end
    end
  end
end
