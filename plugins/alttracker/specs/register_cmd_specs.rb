require "plugin_test_loader"

module AresMUSH
  module AltTracker

    describe RegisterPlayerCmd do
      before do
        @client = double
        @enactor = double
        @player = double
        stub_translate_for_testing
        allow(@player).to receive(:banned) { nil }
        allow(@player).to receive(:codeword) { "Secret" }
        allow(Pf2noms).to receive(:calculate_max_alts) { 5 }
        allow(Pf2noms).to receive(:calculate_current_alts) { 1 }
      end

      def run(command_text)
        handler = RegisterPlayerCmd.new(@client, Command.new(command_text), @enactor)
        handler.parse_args
        handler.handle
      end

      context "with an email that is not on file" do
        it "creates a player and registers the character" do
          allow(AltTracker).to receive(:find_player_by_email).with("new@example.com", @enactor) { nil }
          expect(Player).to receive(:create).with(name: "new@example.com", codeword: "word") { @player }
          expect(@enactor).to receive(:update).with(player: @player)
          expect(@client).to receive(:emit_success).with("alttracker.register_ok")
          run("register new@example.com=word")
        end
      end

      context "with an email that is already on file" do
        before do
          allow(AltTracker).to receive(:find_player_by_email).with("taken@example.com", @enactor) { @player }
        end

        it "says the email is already registered when the code word does not match" do
          expect(@client).to receive(:emit_failure).with("alttracker.email_already_registered")
          run("register taken@example.com=wrong")
        end

        it "treats the code word as case-sensitive" do
          expect(@client).to receive(:emit_failure).with("alttracker.email_already_registered")
          run("register taken@example.com=secret")
        end

        it "registers the character when the code word matches" do
          expect(@enactor).to receive(:update).with(player: @player)
          expect(@player).to receive(:update).with(mark_idle: nil)
          expect(@client).to receive(:emit_success).with("alttracker.register_ok")
          run("register taken@example.com=Secret")
        end
      end

      context "with a character name" do
        before do
          @alt = double
          allow(@alt).to receive(:player) { @player }
          allow(Character).to receive(:find_one_by_name).with("Altname") { @alt }
        end

        it "reports an invalid code word when it does not match" do
          expect(@client).to receive(:emit_failure).with("alttracker.invalid_codeword")
          run("register Altname=wrong")
        end

        it "asks for an email when the character is not registered" do
          allow(@alt).to receive(:player) { nil }
          expect(@client).to receive(:emit_failure).with("alttracker.must_use_email")
          run("register Altname=word")
        end
      end
    end

    describe ViewAltsCmd do
      before do
        @client = double
        @enactor = double
        @player = double
        stub_translate_for_testing
        allow(@enactor).to receive(:has_permission?).with("manage_alts") { true }
        allow(@player).to receive(:name) { "taken@example.com" }
        allow(@player).to receive(:codeword) { "Secret" }
        allow(@player).to receive(:banned) { nil }
        allow(AltTracker).to receive(:get_altlist_by_object).with(@player) { [ "Altname" ] }
      end

      it "looks up a player by email for staff" do
        expect(AltTracker).to receive(:find_player_by_email).with("taken@example.com", @enactor) { @player }
        expect(@client).to receive(:emit)
        handler = ViewAltsCmd.new(@client, Command.new("alts taken@example.com"), @enactor)
        handler.parse_args
        handler.handle
      end
    end

  end
end
