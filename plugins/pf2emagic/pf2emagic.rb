$:.unshift File.dirname(__FILE__)

module AresMUSH
  module Pf2emagic

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    def self.shortcuts
      Global.read_config("pf2emagic", "shortcuts")
    end

    # Each command reads a sheet once between its writes (`Pf2e::SheetReads.during`), as pf2e's and pf2egear's do.
    # Without it, prepare/familiar read the same records from Redis over and over and took over half a second.
    def self.get_cmd_handler(client, cmd, enactor)
      Pf2e::ReadsOnce.wrapped(cmd_handler(client, cmd, enactor))
    end

    def self.cmd_handler(client, cmd, enactor)
      case cmd.root
      when "addspell"
        return PF2ChargenSpellsCmd
      when "prepared"
        return PF2DisplayPreparedCmd
      when "prepare"
        # A switch names a book a feat keeps (prepare/esotericpolymath), a feat that changes what a slot
        # holds (prepare/splitslot, prepare/spellmastery), or a daily choice a feat has the character make
        # (prepare/longevity). Each feat's data names its own.
        # prepare/staff prepares a staff for the day (Pf2e::Staves). prepare/swap and prepare/reprepare
        # change a prepared spell after daily preparations (PreparedSwaps).
        return PF2PrepareSpellCmd unless cmd.switch
        return Pf2e::PF2PrepareStaffCmd if cmd.switch.downcase == 'staff'
        return PF2PrepareSwapCmd if %w{swap reprepare}.include?(cmd.switch.downcase)
        return Pf2e::PF2PrepareDailyCmd if Pf2e::DailyChoices.switch?(cmd.switch)
        return SlotFeats.switch?(cmd.switch) ? PF2PrepareSlotFeatCmd : PF2PrepareFromBookCmd
      when "unprepare"
        return PF2UnprepareSpellCmd unless cmd.switch
        return Pf2e::PF2UnprepareStaffCmd if cmd.switch.downcase == 'staff'
        return Pf2e::PF2UnprepareDailyCmd if Pf2e::DailyChoices.switch?(cmd.switch)
        return PF2UnprepareSlotFeatCmd
      when "spell"
        case cmd.switch
        when "search"
          return PF2SearchSpellCmd
        when "eligible"
          return PF2SpellEligibleCmd
        when "learn"
          return PF2LearnSpellCmd
        when nil
          return PF2DisplaySpellCmd
        end
      when "magic"
        return PF2MagicDisplayCmd
      when "spellbook"
        return PF2MagicSpellbookCmd
      when "repertoire"
        return PF2MagicRepertoireCmd
      when 'dfont'
        return PF2DivineFontCmd
      end
    end

    def self.get_event_handler(event_name)
      nil
    end

    # A page reads each sheet once between its writes, as a command does.
    def self.get_web_request_handler(request)
      case request.cmd
      when "pf2ProfileSpells"
        return Pf2e::ReadsOnce.wrapped(PF2ProfileSpellsHandler)
      end

      nil
    end

  end
end
