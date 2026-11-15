require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # For the length of a command, a read the database was already asked is answered from what it said,
    # until anything is written: by this command, or by anyone else.
    # Every command sent to the database while `on`, by name.
    module SentToDatabase
      class << self; attr_accessor :on, :sent; end

      def write(args)
        SentToDatabase.sent << args.first.to_s.upcase if SentToDatabase.on
        super
      end
    end
    Redic::Client.prepend(SentToDatabase) unless Redic::Client < SentToDatabase

    # A worked-out answer, kept by a key of the caller's own for the length of a command, until anything
    # is written.
    describe "ReadCache.kept" do
      def worked(counter, key = [ :answer, 'Character', '1' ])
        ReadCache.kept(key) { counter[:worked] += 1 }
      end

      it "should work an answer out once in a command" do
        counter = { :worked => 0 }

        ReadCache.during { 3.times { worked(counter) } }

        expect(counter[:worked]).to eq 1
      end

      it "should keep each key's answer apart" do
        counter = { :worked => 0 }

        ReadCache.during { 2.times { [ '1', '2' ].each { |id| worked(counter, [ :answer, 'Character', id ]) } } }

        expect(counter[:worked]).to eq 2
      end

      it "should work it out again after a write" do
        counter = { :worked => 0 }

        ReadCache.during do
          worked(counter)
          ReadCache.written!
          worked(counter)
        end

        expect(counter[:worked]).to eq 2
      end

      it "should keep nothing written while it was being worked out" do
        counter = { :worked => 0 }

        ReadCache.during do
          ReadCache.kept([ :answer ]) { ReadCache.written! }
          ReadCache.kept([ :answer ]) { counter[:worked] += 1 }
        end

        expect(counter[:worked]).to eq 1
      end

      it "should keep nothing outside a command" do
        counter = { :worked => 0 }

        2.times { worked(counter) }

        expect(counter[:worked]).to eq 2
      end
    end

    describe ReadCache, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Reader#{rand(1000000)}")
        @sent = SentToDatabase.sent = []
        SentToDatabase.on = true
      end

      after(:each) do
        SentToDatabase.on = false
        @char.delete
      end

      def reads
        @sent.count { |one| one == 'HGETALL' }
      end

      it "should answer a read it was already given" do
        ReadCache.during { 3.times { Character[@char.id] } }

        expect(reads).to eq 1
      end

      it "should read again after a write" do
        names = ReadCache.during do
          first = Character[@char.id].name
          Character[@char.id].update(:name => "#{first}x")
          [ first, Character[@char.id].name ]
        end

        expect(names.last).to eq "#{names.first}x"
      end

      it "should read again after another thread writes" do
        names = ReadCache.during do
          first = Character[@char.id].name
          Thread.new { Character[@char.id].update(:name => "#{first}y") }.join
          [ first, Character[@char.id].name ]
        end

        expect(names.last).to eq "#{names.first}y"
      end

      it "should answer reads made together once it has them all" do
        3.times { |at| PF2Gear.create(:name => "Rope #{at}", :character => @char) }

        ReadCache.during { 2.times { Character[@char.id].gear.to_a } }

        expect(reads).to eq 1 + 3
        PF2Gear.find(:character_id => @char.id).each(&:delete)
      end

      it "should answer a find by two indices without taking it for a write" do
        ReadCache.during do
          2.times { Pf2eCombatantState.find(:encounter_id => 'none', :character_id => @char.id).to_a }
          Character[@char.id]
          Character[@char.id]
        end

        expect([ @sent.count('EVALSHA'), reads ]).to eq [ 1, 1 ]
      end

      it "should hold nothing past the command" do
        ReadCache.during { Character[@char.id] }
        Character[@char.id]

        expect(reads).to eq 2
      end

      it "should give each reader its own copy" do
        ReadCache.during do
          Character[@char.id].name << 'z'
          expect(Character[@char.id].name).to eq @char.name
        end
      end
    end
  end
end
