require "plugin_test_loader"

module AresMUSH
  module EaEvents

    # Reading a typed level range and labeling a stored one. The tiers are stubbed so the specs
    # don't move when staff change the config.
    describe "event level ranges" do
      before(:each) do
        tiers = [ [1, 4], [5, 8], [9, 12], [13, 16], [17, 20] ].each_with_index.map do |(min, max), i|
          { 'name' => "T#{i + 1}", 'min' => min, 'max' => max }
        end
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with("eaevents", "level_tiers").and_return(tiers)
      end

      def parse(text)
        EaEvents.parse_level_range(text)
      end

      it "should read levels, tiers, spans of tiers, and any" do
        expect(parse("5-8")).to eq [ [5, 8], nil ]
        expect(parse("7")).to eq [ [7, 7], nil ]
        expect(parse("T2")).to eq [ [5, 8], nil ]
        expect(parse("t2 - T3")).to eq [ [5, 12], nil ]
        expect(parse("any")).to eq [ [1, 20], nil ]
      end

      it "should put a reversed range the right way round" do
        expect(parse("8-5")).to eq [ [5, 8], nil ]
        expect(parse("T3-T2")).to eq [ [5, 12], nil ]
      end

      it "should read none or blank as no range" do
        expect(parse("none")).to eq [ nil, nil ]
        expect(parse("")).to eq [ nil, nil ]
      end

      it "should refuse levels past the cap, unknown tiers, and other text" do
        [ "0", "21", "5-21", "T6", "lots", "1-2-3", "5-" ].each do |text|
          range, error = parse(text)
          expect(range).to be_nil, text
          expect(error).to eq t('eaevents.invalid_level_range', :cap => 20)
        end
      end

      it "should label a range on tier boundaries as tiers" do
        expect(EaEvents.level_range_label([5, 8])).to eq "T2 (Levels 5-8)"
        expect(EaEvents.level_range_label([5, 12])).to eq "T2-T3 (Levels 5-12)"
        expect(EaEvents.level_range_label([5, 12], :short)).to eq "T2-T3"
        expect(EaEvents.level_range_label([5, 8], :sr)).to eq "T2, levels 5 to 8"
        expect(EaEvents.level_range_label([5, 12], :sr)).to eq "T2 to T3, levels 5 to 12"
      end

      it "should label the full range as any level" do
        expect(EaEvents.level_range_label([1, 20])).to eq "Any level (1-20)"
        expect(EaEvents.level_range_label([1, 20], :short)).to eq "Any level"
        expect(EaEvents.level_range_label([1, 20], :sr)).to eq "any level"
      end

      it "should label any other range as levels" do
        expect(EaEvents.level_range_label([3, 6])).to eq "Levels 3-6"
        expect(EaEvents.level_range_label([3, 6], :short)).to eq "Lv 3-6"
        expect(EaEvents.level_range_label([3, 6], :sr)).to eq "levels 3 to 6"
        expect(EaEvents.level_range_label([7, 7])).to eq "Level 7"
        expect(EaEvents.level_range_label([7, 7], :short)).to eq "Lv 7"
        expect(EaEvents.level_range_label(nil)).to eq ""
      end

      it "should read the portal's From and To levels" do
        expect(EaEvents.parse_web_level_range('min_level' => '12', 'max_level' => '5')).to eq [ [5, 12], nil ]
        expect(EaEvents.parse_web_level_range('min_level' => 7, 'max_level' => '')).to eq [ [7, 7], nil ]
        expect(EaEvents.parse_web_level_range('min_level' => '', 'max_level' => nil)).to eq [ nil, nil ]
        expect(EaEvents.parse_web_level_range('min_level' => 'T2', 'max_level' => '')[1]).not_to be_nil
        expect(EaEvents.parse_web_level_range('min_level' => '1', 'max_level' => '25')[1]).not_to be_nil
      end
    end
  end
end
