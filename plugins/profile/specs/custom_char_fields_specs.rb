require "plugin_test_loader"

module AresMUSH
  module Profile

    describe CustomCharFields do
      before do
        @player = double("player", name: "me@example.com")
        @char = double("char", player: @player)
        allow(AltTracker).to receive(:get_altlist_by_object).with(@player) { [ "Alpha", "Beta" ] }
        allow(Website).to receive(:format_markdown_for_html) { |text| text }
      end

      def viewer(player: nil, staff: false)
        v = double("viewer", player: player)
        allow(v).to receive(:has_permission?).with("manage_alts") { staff }
        v
      end

      it "shows registration to another alt of the same player" do
        fields = CustomCharFields.get_fields_for_viewing(@char, viewer(player: @player))
        expect(fields[:show_registration]).to eq true
        expect(fields[:alttracker_register]).to eq "me@example.com"
        expect(fields[:alttracker_alts]).to eq "Alpha, Beta"
      end

      it "shows registration to alt-tracker staff" do
        fields = CustomCharFields.get_fields_for_viewing(@char, viewer(player: double("other"), staff: true))
        expect(fields[:show_registration]).to eq true
      end

      it "hides registration from another player" do
        fields = CustomCharFields.get_fields_for_viewing(@char, viewer(player: double("other")))
        expect(fields).to eq({})
      end

      it "hides registration from an unregistered viewer" do
        fields = CustomCharFields.get_fields_for_viewing(@char, viewer(player: nil))
        expect(fields).to eq({})
      end

      it "hides registration from a viewer who is not logged in" do
        expect(CustomCharFields.get_fields_for_viewing(@char, nil)).to eq({})
      end

      it "tells a character's own player that it is not yet registered" do
        unregistered = double("char", player: nil)
        fields = CustomCharFields.get_fields_for_viewing(unregistered, unregistered)
        expect(fields[:show_registration]).to eq true
        expect(fields[:alttracker_register]).to eq "Not yet registered."
        expect(fields[:alttracker_alts]).to eq "None."
      end
    end

  end
end
