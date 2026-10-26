require "aresmush"

module AresMUSH

  # The specs' own Redis database (AresMUSH::SpecDatabase, in spec_helper.rb). A spec that reached the
  # game's database could stop the scenes players are in, or - through Install.init_db's fallback - empty
  # it and change the server's password, so the guard is checked like anything else.
  describe "the spec database guard" do
    it "should refuse a connection that names no database, as Install.init_db's fallback opens" do
      expect { Redic.new("redis://127.0.0.1:6379") }.to raise_error(SecurityError, /not Redis database #{SpecDatabase::DB}/)
    end

    it "should refuse the game's database by number, without repeating the password" do
      expect { Redic.new("redis://:secret@127.0.0.1:6379/0") }.to raise_error(SecurityError) { |error|
        expect(error.message).to_not include('secret')
      }
    end

    it "should allow the spec database" do
      expect { Redic.new("redis://127.0.0.1:6379/#{SpecDatabase::DB}") }.to_not raise_error
    end

    it "should never be the game's own database" do
      expect(SpecDatabase::DB).to_not eq 0
    end
  end
end
