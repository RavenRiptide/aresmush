module AresMUSH
  module Pf2e

    # A Hero Point spent on a check: it is rolled again, or 10 is added to a roll that came up under 10.
    # Either is a fortune effect, so a check takes one Hero Point and no more, and none where it was
    # already rolled twice.
    #
    # The check is the last one the character made in the last change to the encounter they are in - their
    # own Strike, or their save against something the GM did - or else their last `roll` in the scene.
    # That change is taken back and made again with every die as it fell but theirs (`DiceTape`), so what
    # followed from the old result is gone and what follows from the new one happens: the damage, the
    # condition, the action spent. Everyone else's dice stand.
    #
    # It has to be the last change. Once the fight has moved on, the moment for a Hero Point has passed,
    # which is the rule at a table too; a GM can still take the fight back to it with `+e/undo`.
    module HeroFortune

      MODES = { 'reroll' => nil, 'boost' => 10 }.freeze

      # A client for a command made again on behalf of someone who is not connected: it keeps what was
      # refused and drops the rest.
      class QuietClient
        attr_reader :failures

        def initialize(char)
          @char = char
          @failures = []
        end

        attr_reader :char

        def emit_failure(message)
          @failures << message.to_s
        end

        %w{emit emit_success emit_ooc emit_raw}.each { |name| define_method(name) { |_message| nil } }

        def logged_in?
          true
        end

        def screen_reader
          false
        end
      end

      # The check of theirs a Hero Point would change, and where it is: `{ 'row', 'entry' }` in an
      # encounter's history, `{ 'row', 'roll' }` for a `roll`. The later of the two where there are both.
      def self.last_check(char, encounter, scene)
        entry = encounter ? History.latest(encounter) : nil
        fought = entry ? DiceTape.last_check(entry.dice, char.name) : nil
        rolled = (char.pf2_last_check || {})['scene'].to_s == scene&.id.to_s ? char.pf2_last_check : nil
        plain = rolled ? DiceTape.last_check(rolled['dice'], char.name) : nil

        found = if fought && plain
                  entry.created_at.to_f >= rolled['at'].to_f ? { 'row' => fought, 'entry' => entry } : { 'row' => plain, 'roll' => rolled }
                elsif fought then { 'row' => fought, 'entry' => entry }
                elsif plain then { 'row' => plain, 'roll' => rolled }
                end

        return Err.new(:hero_no_check, 'pf2e.hero_no_check') unless found
        return Err.new(:hero_already, 'pf2e.hero_already') if found['row']['hero']
        return Err.new(:hero_fortune, 'pf2e.hero_fortune') if found['row']['kept']

        Ok.new(:state => found)
      end

      # What a mode would make of that check, or why it may not: 10 is added only to a roll under 10.
      def self.face_for(mode, row)
        die = row['faces'].first.to_i

        return Err.new(:hero_not_low, 'pf2e.hero_not_low', 'die' => die) if mode == 'boost' && die >= 10

        Ok.new(:state => mode == 'boost' ? die + MODES['boost'] : nil)
      end

      # The command that was typed, as its typist would type it again.
      def self.command_of(said)
        name, text = said.to_s.split(': ', 2)
        typist = Character.find_one_by_name(name)

        return nil unless typist && text

        cmd = Command.new(text)
        client = Login.find_game_client(typist) || QuietClient.new(typist)
        CommandAliasParser.substitute_aliases(typist, cmd, Global.plugin_manager.shortcuts)
        handler = Global.plugin_manager.sorted_plugins.lazy.select { |plugin| plugin.respond_to?(:get_cmd_handler) }
                        .map { |plugin| plugin.get_cmd_handler(client, cmd, typist) }.find { |found| found }

        handler ? handler.new(client, cmd, typist) : nil
      end

      # Makes the check again. Answers the die it was and the die it is.
      def self.again(char, found, face)
        was = found['row']['faces'].first.to_i
        made = found['entry'] ? fought_again(char, found['entry'], face) : rolled_again(char, found['roll'], face)

        return made if made.err?

        Ok.new(:state => { 'was' => was, 'now' => made.state['faces'].first.to_i })
      end

      # In an encounter: the change is taken back and made again. If that comes to nothing - the command
      # is refused now, or never reaches their check - the encounter is put back as it was.
      def self.fought_again(char, entry, face)
        encounter = PF2Encounter[entry.encounter_id]
        kept = %i{seq said before after dice heroes}.to_h { |field| [ field, entry.public_send(field) ] }
        command = command_of(entry.said)

        return Err.new(:hero_no_replay, 'pf2e.hero_no_replay') unless command

        undone = History.undo(encounter)

        return undone if undone.err?

        begin
          DiceTape.replaying(kept[:dice], :who => char.name, :face => face) { command.on_command }
        rescue StandardError => e
          Global.logger.error "A Hero Point's replay of '#{kept[:said]}' failed: #{e.message} #{e.backtrace&.first}"
        end

        made = History.latest(PF2Encounter[encounter.id])
        row = made && made.seq == kept[:seq] ? DiceTape.last_check(made.dice, char.name) : nil

        unless row && row['hero']
          put_back(encounter, kept)

          return Err.new(:hero_no_replay, 'pf2e.hero_no_replay')
        end

        made.update(:heroes => Array(kept[:heroes]) + [ char.name ])

        Ok.new(:state => row)
      end

      # The encounter and its history as an entry left them.
      def self.put_back(encounter, kept)
        History.restore(encounter, kept[:after])
        History.entries(encounter).select { |one| one.seq >= kept[:seq] }.each(&:delete)
        Pf2eEncounterEntry.create(kept.merge(:encounter => encounter))
        PF2Encounter[encounter.id].update(:history_at => kept[:seq])
      end

      # A `roll`: typed again with their d20 changed.
      def self.rolled_again(char, roll, face)
        command = command_of("#{char.name}: #{roll['raw']}")

        return Err.new(:hero_no_replay, 'pf2e.hero_no_replay') unless command

        DiceTape.replaying(roll['dice'], :who => char.name, :face => face) { command.on_command }

        row = DiceTape.last_check((Character[char.id].pf2_last_check || {})['dice'], char.name)

        row && row['hero'] ? Ok.new(:state => row) : Err.new(:hero_no_replay, 'pf2e.hero_no_replay')
      end
    end
  end
end
