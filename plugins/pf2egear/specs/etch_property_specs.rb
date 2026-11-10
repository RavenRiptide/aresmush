require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # Etching a property rune onto an item.
    #
    # The command took any word at all and wrote it onto a list nothing read, so a typo and a rune were
    # the same thing. A rune is now a catalogue entry carrying what it does, so a name the catalogue does
    # not have is refused - and an item holds as many property runes as its potency rune is worth, which
    # is the rule as written.
    describe "etching a property rune", :dbtest => true do

      class EtchClient
        attr_reader :successes, :failures

        def initialize
          @successes = []
          @failures = []
        end

        def logged_in?
          true
        end

        def emit_success(msg)
          @successes << msg.to_s
        end

        def emit_failure(msg)
          @failures << msg.to_s
        end

        def emit(msg)
          @successes << msg.to_s
        end

        def emit_ooc(msg)
          @successes << msg.to_s
        end

        def to_s
          "EtchClient"
        end
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = EtchClient.new
        @char = Character.create(:name => "Etch#{rand(1000000)}")
        @char.update(:pf2_level => 10)
        # The command is for staff, and the character is re-read between runs, so the permission is
        # granted to the class rather than to one object.
        allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)

        info = Global.read_config('pf2e_weapons', 'Longsword')
        @sword = Pf2egear.create_item(@char, 'weapons', 'Longsword', 1, info)
        @sword.update(:runes => { 'fundamental' => { 'potency' => 1 }, 'property' => { 'list' => [] } })
      end

      after(:each) do
        @sword&.delete
        @char&.delete
      end

      # The index is the position in the list the player sees, which starts at nothing.
      def etch(rune)
        handler = PF2EtchPropertyCmd.new(@client, Command.new("etch/property #{@char.name}=weapons/0/#{rune}"),
                                         Character[@char.id])
        handler.on_command
        @sword = PF2Weapon[@sword.id]

        handler
      end

      def etched
        Array(@sword.runes.dig('property', 'list'))
      end

      it "should etch a rune the catalogue has" do
        etch 'Flaming'

        expect(@client.failures).to eq []
        expect(etched).to eq [ 'Flaming' ]
      end

      it "should take it off again when it is already there" do
        etch 'Flaming'
        etch 'Flaming'

        expect(etched).to eq []
      end

      # The point of the catalogue: a name nothing matches would be a word on an item and no mechanics.
      it "should refuse a rune the catalogue does not have" do
        etch 'Flamming'

        expect(@client.failures.join).to include 'Flamming'
        expect(etched).to eq []
      end

      it "should refuse an armour rune on a weapon" do
        etch 'Slick'

        expect(@client.failures).to_not eq []
        expect(etched).to eq []
      end

      # A weapon holds as many property runes as its potency rune is worth.
      it "should refuse one more than the item has room for" do
        etch 'Flaming'
        etch 'Corrosive'

        expect(@client.failures).to_not eq []
        expect(etched).to eq [ 'Flaming' ]
      end

      it "should allow the second once the potency rune is higher" do
        etch 'Flaming'
        @sword.update(:runes => @sword.runes.merge('fundamental' => { 'potency' => 2 }))
        etch 'Corrosive'

        expect(@client.failures).to eq []
        expect(etched).to eq %w{Corrosive Flaming}
      end

      # Taking one off is always allowed, which is what puts an over-runed item right.
      it "should let a rune be taken off an item with no room left" do
        etch 'Flaming'
        @sword.update(:runes => @sword.runes.merge('fundamental' => { 'potency' => 0 }))
        etch 'Flaming'

        expect(etched).to eq []
      end

      # The fit is the vendor's too (`RuneFit`), so a staff etch can't put on what the vendor would refuse.
      it "should refuse a rune the item isn't the kind it's etched onto" do
        etch 'Returning'

        expect(@client.failures.join).to include 'a thrown weapon'
        expect(etched).to eq []
      end

      it "should put a stronger rune in place of a weaker one of its family" do
        etch 'Flaming'
        etch 'Greater Flaming'

        expect(@client.failures).to eq []
        expect(etched).to eq [ 'Greater Flaming' ]
        expect(@client.successes.last).to include 'replacing Flaming'
      end

      # A rune the catalogue no longer has can still be taken off, by the name it was etched with.
      it "should take off a rune the catalogue no longer has" do
        @sword.update(:runes => @sword.runes.merge('property' => { 'list' => [ 'Speed' ] }))
        etch 'Speed'

        expect(@client.failures).to eq []
        expect(etched).to eq []
      end

      it "should take off a rune spelled the pack's way by the catalogue's name" do
        @sword.update(:runes => @sword.runes.merge('property' => { 'list' => [ 'Flaming (Greater)' ] }))
        etch 'Greater Flaming'

        expect(etched).to eq []
      end
    end
  end
end
