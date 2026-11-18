require "plugin_test_loader"

module AresMUSH
  module Demographics
    describe Demographics do
      describe :parse_birthdate_input do
        before do
          allow(Global).to receive(:read_config).with("ictime", "month_names") {
            [ "Darkfeast", "Balefire", "Shadowfall", "Starmask", "Paramount", "Highsun",
              "Skydance", "Fireside", "Revel", "Highhunt", "Gathering", "Yule" ]
          }
          allow(Global).to receive(:read_config).with("ictime", "year_offset") { -998 }
          allow(ICTime).to receive(:ictime) { DateTime.new(1028, 11, 18) }
        end

        it "converts an RL month and RL year" do
          expect(Demographics.parse_birthdate_input("January 20 1993")).to eq Date.new(995, 1, 20)
        end

        it "reads a lowercase Ea month with a comma and an IC year" do
          expect(Demographics.parse_birthdate_input("darkfeast 20, 995")).to eq Date.new(995, 1, 20)
        end

        it "reads M/D/Y with an RL year" do
          expect(Demographics.parse_birthdate_input("1/20/1993")).to eq Date.new(995, 1, 20)
        end

        it "leaves an IC year alone" do
          expect(Demographics.parse_birthdate_input("Gathering 5 1000")).to eq Date.new(1000, 11, 5)
        end

        it "strips surrounding spaces" do
          expect(Demographics.parse_birthdate_input("  Yule 1 1000  ")).to eq Date.new(1000, 12, 1)
        end

        it "returns nil for an impossible day" do
          expect(Demographics.parse_birthdate_input("Balefire 31 995")).to be_nil
        end

        it "returns nil for an impossible month number" do
          expect(Demographics.parse_birthdate_input("13/1/995")).to be_nil
        end

        it "returns nil for an unknown month name" do
          expect(Demographics.parse_birthdate_input("Smarch 1 995")).to be_nil
        end

        it "returns nil for blank input" do
          expect(Demographics.parse_birthdate_input("")).to be_nil
          expect(Demographics.parse_birthdate_input(nil)).to be_nil
        end
      end
    end
  end
end
