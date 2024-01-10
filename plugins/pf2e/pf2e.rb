$:.unshift File.dirname(__FILE__)

module AresMUSH
  module Pf2e

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    def self.shortcuts
      Global.read_config("pf2e", "shortcuts")
    end

    def self.get_cmd_handler(client, cmd, enactor)
      case cmd.root
      when 'timefmt'
        return PF2TimeFmtCmd
      when "damage"
        return PF2DamagePlayerCmd
      when "sheet"
        case cmd.switch
        when "show"
          return PF2ShowSheetCmd
        when "combat"
          return PF2DisplayCombatSheetCmd
        else
          return PF2DisplaySheetCmd
        end
      when "award"
        case cmd.switch
        when "xp"
          return PF2AwardXPCmd
        end
      when "cg"
        case cmd.switch
        when "set"
          return PF2SetChargenCmd
        when "review"
          return PF2ReviewChargenCmd
        when "reset"
          return PF2ResetChargenCmd
        when "info"
          return PF2ChargenInfoCmd
        end
      when "commit"
        case cmd.args
        when "info"
          return PF2CommitInfoCmd
        when "abilities"
          return PF2CommitAbilCmd
        end
      when "roll"
        case cmd.switch
        when nil, "me"
          return PF2RollCommand
        when "for"
          return PF2RollForCommand
        when "listalias"
          return PF2ListRollAliasCmd
        when "alias"
          return PF2ChangeRollAliasCmd
        end
      when "boost"
        case cmd.switch
        when "set"
          return PF2BoostSetCmd
        when "unset"
          return PF2BoostUnsetCmd
        end
      when "skill"
        case cmd.switch
        when "set"
          return PF2SkillSetCmd
        when "unset"
          return PF2SkillUnSetCmd
        end
      when "lang"
        case cmd.switch
        when "set"
          return PF2LanguageSetCmd
        when "info"
          return PF2LanguageInfoCmd
        when "unset"
          return PF2LanguageUnSetCmd
        end
      when "feat"
        case cmd.switch
        when "set"
          return PF2FeatSetCmd
        when "info"
          return PF2FeatInfoCmd
        when "options"
          return PF2FeatOptionsCmd
        when "search"
          return PF2FeatSearchCmd
        else
          return PF2FeatDisplayOneCmd
        end
      when "knownfor"
        return PF2KnownForCmd
      when "encounter", "initiative", "init"
        case cmd.switch
        when "start"
          return PF2InitiateCombatCmd
        when "view"
          return PF2InitViewCmd
        when "join"
          return PF2InitJoinCmd
        when "next"
          return PF2EncounterNextCmd
        when "prev"
          return PF2EncounterPrevCmd
        when "mod"
          return PF2InitModCmd
        when "add"
          return PF2EncounterAddCmd
        when "scan"
          return PF2EncounterScanCmd
        when "end"
          return PF2EncounterEndCmd
        when "restart"
          return PF2EncounterRestartCmd
        else 
          return PF2InitiateCombatCmd
        end
      when "tinit"
        return PF2InitViewCmd
      when "ninit"
        return PF2EncounterNextCmd
      when "pinit"
        return PF2EncounterPrevCmd
      when "rminit"
        return PF2EncounterRemoveCmd
      when "jinit"
        return PF2EncounterAddCmd
      when "tscan"
        return PF2EncounterScanCmd
      when "resume"
        return PF2EncounterEndCmd
      when "admin"
        case cmd.switch
        when "set"
          return PF2AdminSetCmd
        end
      end

      nil
    end

    def self.get_event_handler(event_name)
      nil
    end

    def self.get_web_request_handler(request)
      case request.cmd
      when "pf2_feats_all"
        return PF2FeatsAllHandler
      end

      nil
    end

  end
end
