require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The engine answers events; the room, `+e/why` and the portal render them. An event survives being
    # stored on a character and read back, and its values render the same wherever they are told.
    describe Telling do

      before(:each) do
        allow(AresMUSH::Locale).to receive(:translate) do |key, **args|
          "#{key}[#{args.map { |name, value| "#{name}=#{value}" }.join(';')}]"
        end
      end

      it "should render a roll with its die, the fortune it was rolled with, or what stood in for it" do
        expect(Telling.value(Telling.roll('total' => 23, 'die' => 15, 'modifier' => 8))).to eq '23 (15 +8)'
        expect(Telling.value(Telling.roll('total' => 23, 'dice' => [ 15, 7 ], 'kept' => 'keep-higher', 'modifier' => 8)))
          .to eq '23 (fortune: 15, 7 +8)'
        expect(Telling.value(Telling.roll('total' => 18, 'modifier' => 8,
                                          'substitution' => { 'slug' => 'assurance', 'label' => 'Assurance' })))
          .to eq '18 (Assurance 10 +8)'
      end

      it "should colour a degree, as a hit for an attack and a success otherwise" do
        expect(Telling.value(Telling.degree(3, true))).to eq '%xh%xmcritical hit%xn'
        expect(Telling.value(Telling.degree(1, false))).to eq '%xyfailure%xn'
      end

      it "should render an event inside another, and a list of them joined" do
        inner = Telling.event('pf2e.act_flanking')
        outer = Telling.event('pf2e.act_circumstances', :list => [ inner, 'concealed' ])

        expect(Telling.render(outer)).to eq 'pf2e.act_circumstances[list=pf2e.act_flanking[], concealed]'
      end

      it "should tell text stored before events were, as it was" do
        expect(Telling.lines([ 'Fist - attack 12 (4 +8):' ])).to eq [ 'Fist - attack 12 (4 +8):' ]
      end
    end
  end
end
