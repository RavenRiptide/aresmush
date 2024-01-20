module AresMUSH
  module Pf2emagic

    def generate_spells_today(obj, charclass)
      # Function assumes that calling code has already validated the magic object.

      caster_class = charclass.downcase

      case caster_class
      when "wizard", "druid", "cleric", "witch"
        prepared_list = obj.spells_prepared

        obj.update(spells_today: prepared_list)
      when "bard", "oracle", "sorcerer"
        spells_today = generate_blank_spell_list(obj)

        obj.update(spells_today: spells_today)
      else
        return nil
      end

    end

    def generate_blank_spell_list(obj)
      prepared_list = {}
      spells_per_day = obj.spells_per_day

      spells_per_day.each_pair do |level, count|
        list = Array.new(count, "open")

        prepared_list[level] = list
      end

      prepared_list
    end

    def prepare_spell(spell, char, castclass, level, use_arcane_evo=false)
      # All validations are done in the helper.
      magic = char.magic

      return t('pf2emagic.not_caster') if !magic

      cc = castclass.downcase
      tradition = magic.tradition[cc]

      return t('pf2emagic.not_casting_class', :cc => cc) if !tradition

      prepared_cc_list = Global.read_config('pf2e_magic', 'prepared_casters')

      if !(prepared_cc_list.include? cc)
        if !use_arcane_evo
          return t('pf2emagic.does_not_prepare')
        end
      end

      spell_details = Global.read_config('pf2e_spells', spell)

      return t('pf2emagic.no_such_spell') unless spell_details

      needs_spellbook = spell_details['traits'].intersect?('rare', 'uncommon', 'unique')

      if use_arcane_evo || needs_spellbook || castclass == 'wizard'
        is_in_spellbook = spellbook_check(magic, spell)
        return t('pf2emagic.not_in_spellbook') unless is_in_spellbook[0]
        make_signature = is_in_spellbook[1]
      end

      return_msg = {
        "level" => spell_level,
        "name" => spell,
        "caster class" => cc,
        "is_signature" => make_signature
     }

      if make_signature
        signature_spells = magic.signature_spells
        signature_spells["Arcane Evolution"] = [ spell ]
        magic.update(signature_spells: signature_spells)

        return return_msg
      end

      spell_trad = spell_details['tradition']

      return t('pf2emagic.cant_prepare_trad', :cc => cc) unless spell_trad.include? tradition

      spell_level = spell_details['base_level']

      # Level can be passed as nil, if it is, default to the base level of the spell.
      level = spell_level unless level

      return t('pf2emagic.cant_prepare_level') if spell_level > level

      if use_arcane_evo
        repertoire = obj.repertoire
        repertoire['Arcane Evolution'] = [ spell ]
        magic.update(repertoire: repertoire)

        return return_msg
      end

      spell_list_for_level = magic.spells_prepared[level]

      return t('pf2emagic.cant_prepare_level') unless spell_list_for_level

      open_slot = spell_list_for_level.index["open"]

      return t('pf2emagic.no_available_slots') unless open_slot

      # If all checks succeed, prepare the spell and return a hash.

      spell_list_for_level[open_slot] = spell

      magic.spells_prepared[level] = spell_list_for_level
      magic.save

      return_msg

    end

    def unprepare_spell(spell, char, castclass, level=nil)
      # All validations are done in the helper.
      magic = char.magic

      return t('pf2emagic.not_caster') if !magic

      cc = castclass.downcase
      tradition = magic.tradition[cc]

      return t('pf2emagic.not_casting_class', :cc => cc) if !tradition

      prepared_cc_list = Global.read_config('pf2e_magic', 'prepared_casters')

      return t('pf2emagic.does_not_prepare') if !(prepared_cc_list.include? cc)

      prepared_spells = magic.prepared_spells[castclass]

      prepared_levels = []

      prepared_spells.each_pair do |level, list|
        prepared_levels << level if list.include? spell
      end

      return t('pf2emagic.not_prepared') if prepared_levels.empty?
      return t('pf2emagic.specify_level') if (prepared_levels.uniq[1] && !level)
      return t('pf2emagic.not_prepared_at_level') if (level && (!prepared_levels.include? level))

      level_to_mod = level ? level : prepared_levels[0]

      spell_list = prepared_spells[level_to_mod]
      index = spell_list.index(spell)

      spell_list[index] = "open"

      prepared_spells[level_to_mod] = spell_list

      magic.prepared_spells[castclass] = prepared_spells

      magic.save && return
    end

    def spellbook_check(obj, spell)

      # Some classes may have their repertoire automatically written in a spellbook.
      # This is sometimes treated differently if prepared.

      spellbook = obj.spellbook

      repertoire = obj.repertoire

      prepare_ok = true if (spellbook + repertoire).include? spell

      make_signature = true if repertoire.include? spell

      [prepare_ok, make_signature]
    end

    def get_focus_casting_stat(stype)
      Global.read_config('pf2e_magic', 'focus_casting_stat', stype)
    end

    def self.get_caster_type(charclass)
      prepared = Global.read_config('pf2e_magic', 'prepared_casters')
      spont = Global.read_config('pf2e_magic', 'spontaneous_casters')

      return 'prepared' if prepared.include charclass
      return 'spontaneous' if spont.include charclass
      return nil

    end

  end
end
