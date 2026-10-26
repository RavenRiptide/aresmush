require 'rspec'

# figure out where we are being loaded from
if $LOADED_FEATURES.grep(/spec\/spec_helper\.rb/).any?
  begin
    raise "foo"
  rescue => e
    puts <<-MSG
    ===================================================
    It looks like spec_helper.rb has been loaded
    multiple times. Normalize the require to:

    require "spec/spec_helper"

    Things like File.join and File.expand_path will
    cause it to be loaded multiple times.

    Loaded this time from:

    #{e.backtrace.join("\n    ")}
    ===================================================
    MSG
  end
end

module AresMUSH
  
  module SpecHelpers
        
    def stub_translate_for_testing
      # Simple helper to stub out translations.  Only works well if you 
      # have a simple string because it doesn't do anything with the args
      allow(AresMUSH::Locale).to receive(:translate) do |str|
        "#{str}"
      end
    end    
    
    def setup_mock_client(client, char)
      allow(client).to receive(:char) { char }
      allow(char).to receive(:client) { client }
    end
  end  
  
  module GlobalTestHelper
    attr_accessor :config_reader, :client_monitor, :dispatcher, :plugin_manager, :dispatcher, :locale, :help_reader, :notifier
    
    def stub_global_objects
      @config_reader = double
      @client_monitor = double
      @plugin_manager = double
      @dispatcher = double
      @locale = double
      @help_reader = double
      @notifier = double
      
      allow(Global).to receive(:notifier) { @notifier }
      allow(Global).to receive(:config_reader) { @config_reader }
      allow(Global).to receive(:client_monitor) { @client_monitor }
      allow(Global).to receive(:dispatcher) { @dispatcher }
      allow(Global).to receive(:plugin_manager) { @plugin_manager }
      allow(Global).to receive(:locale) { @locale }
      allow(Global).to receive(:help_reader) { @help_reader }
    end
  end  
end


module AresMUSH
  # CUSTOM CODE ADD FOR EMBLEM OF EA: specs keep their data in a Redis database of their own (15, or
  # SPEC_REDIS_DB), never the running game's (0). Sharing it, the game's empty-scene cleanup stopped
  # scenes a spec was playing in, and every spec wrote its characters and scenes into the game.
  module SpecDatabase
    DB = Integer(ENV.fetch('SPEC_REDIS_DB', '15'))

    # Database#load_config, connecting to the spec database instead of the game's.
    module Connecting
      def load_config
        password = Global.read_config("secrets", "database", "password")
        host_and_port = Global.read_config("database", "url")
        Ohm.redis = Redic.new("#{Database.build_url(host_and_port, password)}/#{SpecDatabase::DB}")
        SpecDatabase.seed_once
      end
    end

    # A connection a spec opens names the spec database, or is refused before it is made. This is what
    # keeps Install.init_db's fallback - which reconnects without naming a database, flushes it, and
    # rewrites the server's password - from ever reaching the game's.
    module Guarded
      def new(url = "redis://127.0.0.1:6379", *rest)
        unless url.to_s.end_with?("/#{SpecDatabase::DB}")
          raise SecurityError, "a spec tried to connect to #{url.to_s.sub(/:[^:@\/]*@/, ':***@')}, " \
                               "not Redis database #{SpecDatabase::DB}"
        end

        super
      end
    end

    def self.install!
      raise "SPEC_REDIS_DB must not be 0, the game's own database" if DB.zero?

      Redic.singleton_class.prepend(Guarded)
      Database.prepend(Connecting)
    end

    # Once a run: confirm the connection really is on the spec database, empty it, and set it up the
    # way a new game is set up. Anything going wrong stops the run rather than carrying on elsewhere.
    def self.seed_once
      return if @seeded

      @seeded = true
      held = Ohm.redis.call!('CLIENT', 'INFO').to_s
      unless held.match?(/\bdb=#{DB}\b/)
        abort "The spec database check failed: the connection is on #{held[/db=\d+/] || 'an unknown database'}, " \
              "not db=#{DB}. The run is stopped."
      end

      Ohm.redis.call!('FLUSHDB')
      require File.expand_path('../install/init_db', __dir__)
      quietly { Install.init_db }
    rescue StandardError, SecurityError => e
      abort "Setting up the spec database failed, and the run is stopped: #{e.class}: #{e.message}"
    end

    # Install.init_db narrates as it goes, for someone installing a game; a spec run has no use for it.
    def self.quietly
      require 'stringio'
      shown = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = shown
    end
  end
end


RSpec.configure do |c|
  c.include AresMUSH::SpecHelpers

  # The spec database, set up once the specs have loaded the engine (see AresMUSH::SpecDatabase).
  c.before(:suite) do
    AresMUSH::SpecDatabase.install! if defined?(AresMUSH::Database) && defined?(Redic)
  end

  # List each example for easier test debugging
  # c.default_formatter = 'doc'
  
  $:.unshift File.join(File.dirname(__FILE__), *%w[.. engine])
  $:.unshift File.join(File.dirname(__FILE__), *%w[.. plugins])
end
