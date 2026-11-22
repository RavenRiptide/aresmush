$:.unshift File.dirname(__FILE__)

module AresMUSH
  module Pf2egear

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    def self.shortcuts
      Global.read_config("pf2e_gear_options", "shortcuts")
    end

    # Each command reads a sheet once between its writes (`Pf2e::SheetReads.during`).
    def self.get_cmd_handler(client, cmd, enactor)
      Pf2e::ReadsOnce.wrapped(cmd_handler(client, cmd, enactor))
    end

    def self.cmd_handler(client, cmd, enactor)
      case cmd.root
      when "pay"
        return PF2PayCmd
      when "money"
        return PF2MoneyCmd
      when "browse"
        return PF2BrowseGearCmd
      when "buy"
        return PF2BuyRuneCmd if cmd.switch == "rune"
        return PF2BuyMaterialCmd if cmd.switch == "material"
        return PF2BuyCmd
      when "sell"
        return PF2SellCmd
      when "gear"
        case cmd.switch
        when "rename"
          return PF2GearRenameCmd
        when "equip"
          return PF2GearEquipCmd
        when "unequip"
          return PF2GearUnequipCmd
        when "invest"
          return PF2InvestCmd
        when "uninvest"
          return PF2UninvestCmd
        when "attach", "detach"
          return PF2GearAttachCmd
        else
          return PF2DisplayGearCmd
        end
      when "equip"
        return PF2GearEquipCmd
      when "unequip"
        return PF2GearUnequipCmd
      when "invest"
        return PF2InvestCmd
      when "uninvest"
        return PF2UninvestCmd
      when "bag"
        case cmd.switch
        when "store"
          return PF2BagStoreCmd
        when "retrieve"
          return PF2BagRetrieveCmd
        else
          return PF2BagViewCmd
        end
      when "item"
        case cmd.switch
        when "view"
          return PF2ItemViewCmd
        when "give", "give/free", "give/force"
          return PF2ItemGiveCmd
        end
      when "use"
        return PF2UseItemCmd
      when "wand"
        case cmd.switch
        when "repair"
          return PF2WandRepairCmd
        end
      when "listmoney"
        return PF2ListMoneyCmd
      when "etch"
        case cmd.switch
          when"potency"
            return PF2EtchPotencyCmd
          when "striking"
            return PF2EtchPowerCmd
          when "resilient"
            return PF2EtchPowerCmd
          when "property"
            return PF2EtchPropertyCmd
          when "reinforcing"
            return PF2EtchReinforcingCmd
          end
      end
    end

    def self.get_event_handler(event_name)
      nil
    end

    # A page reads each sheet once between its writes, as a command does.
    def self.get_web_request_handler(request)
      case request.cmd
      when "pf2ProfileInventory"
        return Pf2e::ReadsOnce.wrapped(PF2ProfileInventoryHandler)
      end

      nil
    end

  end
end
