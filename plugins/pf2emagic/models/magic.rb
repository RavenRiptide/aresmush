module AresMUSH
  class PF2Magic < Ohm::Model
    include ObjectModel

    attribute :focus_cantrips, :type => DataType::Hash, :default => {}
    attribute :focus_spells, :type => DataType::Hash, :default => {}
    attribute :focus_pool, :type => DataType::Hash, :default => { "max"=>0, "current"=>0 }
    attribute :last_refocus, :type => DataType::Time
    attribute :innate_spells, :type => DataType::Hash, :default => {}
    attribute :revelation_locked, :type => DataType::Boolean
    attribute :signature_spells, :type => DataType::Hash, :default => {}
    attribute :repertoire, :type => DataType::Hash, :default => {}
    attribute :spell_abil, :type => DataType::Hash, :default => {}
    attribute :spellbook, :type => DataType::Hash, :default => {}
    attribute :spells_per_day, :type => DataType::Hash, :default => {}
    attribute :spells_prepared, :type => DataType::Hash, :default => {}
    attribute :spells_today, :type => DataType::Hash, :default => {}
    attribute :tradition, :type => DataType::Hash, :default => { "innate"=>["innate", "trained"] }
    attribute :prepared_lists, :type => DataType::Hash, :default => {}
    attribute :divine_font

    reference :character, "AresMUSH::Character"


    ##### CLASS METHODS #####

    def self.get_magic_obj(char)
      char.magic
    end

    def self.get_create_magic_obj(char)
      obj = char.magic

      return obj if obj

      obj = PF2Magic.create(character: char)
      char.update(magic: obj)

      return obj
    end

    def self.find_spell_by_name(name)
      term = name.upcase

      list = Global.read_config('pf2e_spells').keys.select { |s| s.upcase.match? term }

      return t('pf2e.multiple_matches', :element => 'spell') if list.size > 1
      return t('pf2e.nothing_to_display', :elements => 'spells') if list.empty?
      return list
    end

    def self.update_magic(char, charclass, info, client)
      magic = get_create_magic_obj(char)

      # Race condition with to_assign requires that to_assign be assembled and returned by the function for a merge.
      to_assign = {}

      info.each_pair do |key, value|
        case key
        when "spell_abil"
          spell_abil = magic.spell_abil
          spell_abil[charclass] = value
          magic.spell_abil = spell_abil

        when "tradition"
          # magic.tradition structure: { charclass => [ trad, prof ] }
          tradition = magic.tradition
          value.each_pair do |trad, prof|
            tradition[charclass] = [ trad, prof ]
          end

          magic.tradition = tradition
        when "spells_per_day"
          # Structure: { charclass => {"cantrip" => 5, 1 => 3, 2 => 1} }
          # This key grants spells per day.

          spells_per_day = magic.spells_per_day
          spd_for_class = spells_per_day[charclass] ? spells_per_day[charclass] : {}

          value.each_pair do |level, num|
            spd_for_class[level] = num
          end

          spells_per_day[charclass] = spd_for_class

          magic.spells_per_day = spells_per_day
        when "repertoire"
          # Structure: { "cantrip" => 5, 1 => 3, 2 => 1 }
          # This key gets dumped into to_assign as repertoire and represents spells that need to be chosen
          # for the repertoire.

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          to_assign["repertoire"] = assignment_list

        when "focus_pool"
          pool = magic.focus_pool

          new_max_pool = Pf2emagic.get_max_focus_pool(char, value)
          pool["max"] = new_max_pool
          magic.focus_pool = pool
        when "addrepertoire"
          # This key is called for spells added to the repertoire by bloodlines, mysteries, etc.
          # Initial/advanced/greater bloodline spells are focus spells and handled by that key.
          # Expected structure of value: { <level> => <spell> }
          repertoire = magic.repertoire
          rep_for_class = repertoire[charclass] || {}

          value.each_pair do |level, spell|
            list = rep_for_class[level] || []
            list << spell
            rep_for_class[level] = list
          end

          repertoire[charclass] = rep_for_class

          magic.repertoire = repertoire
        when "get_genie_repertoire"
          # Value of this key is an integer that corresponds to the level of the spell.
          # It works like repertoire, but what this bloodline gets depends on their genie ancestry.

          genie = char.pf2_base_info['specialize_info']
          spells = Global.read_config('pf2e_subclass', 'get_genie_spell', genie)

          # Do nothing if genie not found.
          next unless spells

          # Grab the spell corresponding to value.
          spell = spells[value]

          next unless spell

          repertoire = magic.repertoire
          rep_for_class = repertoire[charclass]

          rep_at_level = rep_for_class[value] || []

          rep_at_level << spell

          rep_for_class[value] = rep_at_level

          repertoire[charclass] = rep_for_class

          magic.repertoire = repertoire
        when "focus_spell"
          # focus spell structure: { "devotion" => [spell, spell, spell], "revelation" => [spell] }

          focus_spells = magic.focus_spells

          value.each_pair do |fstype, spell_list|
            fs_by_type = focus_spells[fstype] ? focus_spells[fstype] : []
            fs_by_type = (fs_by_type + spell_list).uniq
            focus_spells[fstype] = fs_by_type
          end

          magic.focus_spells = focus_spells
        when "focus_cantrip"
          # Structure identical to focus_spells, kept separate because they are cast differently.

          focus_cantrips = magic.focus_cantrips

          value.each_pair do |fstype, spell_list|
            fs_by_type = focus_cantrips[fstype] ? focus_cantrips[fstype] : []
            fs_by_type = (fs_by_type + spell_list).uniq
            focus_cantrips[fstype] = fs_by_type
          end

          magic.focus_cantrips = focus_cantrips
        when "spellbook"
          # Spells need to be chosen, redirect to to_assign

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          to_assign["spellbook"] = assignment_list

        when "addspellbook"
          # Addspellbook means to add a specific spell to the spellbook. Adding spells to be chosen
          # should be the "spellbook" key.
          # Structure of value for addspell key: { level => [ spell ] }

          spellbook = magic.spellbook

          # Initialize spellbook for class if not already present.
          csb = spellbook[charclass] ? spellbook[charclass] : {}

          value.each do |level, spell_list|
            list = csb[level] ? csb[level] : []

            spell_list.each { |s| list << s }

            csb[level] = list
          end

          spellbook[charclass] = csb
          magic.spellbook = spellbook
        when "signature_spell"
          # This key means that the character needs to pick a spell from their repertoire as a signature spell.
          # Structure of value: { level to pick from => number of spells to add }
          # Use to_assign["signature"]

          assignment_list = {}
          value.each_pair do |level, num|
            ary = Array.new(num, "open")
            assignment_list[level] = ary
          end

          to_assign["signature"] = assignment_list

        when "innate_spell"
          # Structure of innate spells: {spell name => { 'level' => <level>, 'tradition' => tradition, 'cast_stat' => cast_stat}}

          ilist = magic.innate_spells
          key = value.delete('name')

          ilist[key] = value

          magic.innate_spells = ilist
        when "divine_font"
          if value.size > 1

            to_assign['divine font'] = value
          else
            magic.update(divine_font: value.first)
          end
        when 'school_spell'
          # Value in this case is sent to to_assign as { school spell => school }

          to_assign["school spell"] = value['school_spell']
        when 'school_feat'
          # This is called only for universalist wizards.

          to_assign["school feat"] = [ 'open' ]
        else
          client.emit_ooc "Unknown key #{key} in update_magic. Please inform staff."
        end

      end

      magic.save
      char.save

      to_assign
    end

    def self.get_spell_dc(char, charclass, is_focus=false)

      # is_focus should be the focus spell type if given.

      magic = char.magic
      return nil unless magic

      if charclass == "innate"
        spell_abil = "Charisma"
      elsif is_focus
        spell_abil = get_focus_casting_stat(is_focus)
      else
        spell_abil = magic.spell_abil[charclass]
      end

      trad = magic.tradition[charclass]
      prof = trad[1]
      prof_bonus = Pf2e.get_prof_bonus(char, prof)

      abil_mod = Pf2eAbilities.abilmod(
        Pf2eAbilities.get_score char, spell_abil
      )

      10 + abil_mod + prof_bonus
    end

    def self.get_spell_attack_bonus(char, charclass, is_focus=false)

      # is_focus should be the focus spell type if given.

      magic = char.magic
      return nil unless magic

      if charclass == "innate"
        spell_abil = "Charisma"
      elsif is_focus
        spell_abil = get_focus_casting_stat(is_focus)
      else
        spell_abil = magic.spell_abil[charclass]
      end

      trad = magic.tradition[charclass]
      prof = trad[1]
      prof_bonus = Pf2e.get_prof_bonus(char, prof)

      abil_mod = Pf2eAbilities.abilmod(
        Pf2eAbilities.get_score char, spell_abil
      )

      abil_mod + prof_bonus
    end

    def self.factory_default(char)

      magic = char.magic

      # Don't do anything unless magic is created.
      return nil unless magic

      magic.focus_cantrips = {}
      magic.focus_spells = {}
      magic.focus_pool = { "max"=>0, "current"=>0 }
      magic.innate_spells = {}
      magic.signature_spells = {}
      magic.repertoire = {}
      magic.spell_abil = {}
      magic.spellbook = {}
      magic.spells_per_day = {}
      magic.spells_prepared = {}
      magic.spells_today = {}
      magic.tradition = { "innate"=>["innate", "trained"] }
      magic.prepared_lists = {}

      magic.save

    end

  end
end
