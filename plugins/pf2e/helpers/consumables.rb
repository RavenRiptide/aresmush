module AresMUSH
  module Pf2e

    # What a consumable does when it is used in a fight, from what the catalogue says of it
    # (`scripts/import_foundry_consumables.py`):
    #
    #   heal       the Hit Points it restores, rolled; `heal_type` vitality heals only those without void
    #              healing and void only those with it
    #   effect     the `Effect: …` it leaves on whoever takes it
    #   bomb       it is thrown rather than taken: a Strike, with its dice, persistent and splash damage
    #
    # Answers what to tell, in the shape `Acting.report` makes, and leaves the using up to the command.
    module Consumables

      def self.info(name)
        Global.read_config('pf2e_consumables', name) || {}
      end

      def self.bomb?(name)
        info(name).key?('bomb')
      end

      # Someone takes it - the one who used it, or whoever they gave it to. `made_by` is what made the item
      # (its `granted_by`), which decides how long an effect from it may last, and `user` whose it was,
      # whose research field may change what it does: a Chirurgeon's vials heal, and their elixirs fortify.
      def self.take(encounter, given_by, target, name, made_by: nil, user: nil)
        entry = info(name)
        out = Acting.report

        if entry['heal']
          heal(target, name, entry, out, :most => ResearchField.heals_most?(user, name, made_by))
        elsif ResearchField.healing_vial?(user, entry)
          ResearchField.vial_heal(encounter, target, name, entry, user, out)
        elsif ResearchField.mutagen_vial?(user, entry)
          ResearchField.quiet_drawbacks(encounter, target, user, out)
        end

        ResearchField.give_temp_hp(target, ResearchField.fortifying(user, entry, made_by), out)
        ResearchField.mutagen_temp_hp(encounter, target, user, entry, out)

        if entry['effect']
          effect(encounter, given_by, target, entry['effect'], out, item_origin(name, entry),
                 :lasts => quick_cap(entry['effect'], made_by))
        end

        out
      end

      # The most a formula can come to: every die at its highest, and what is added to it.
      def self.highest(formula)
        formula.to_s.delete(' ').scan(/([+-]?)(\d+)(?:d(\d+))?/).sum do |sign, count, sides|
          value = sides ? count.to_i * sides.to_i : count.to_i
          sign == '-' ? -value : value
        end
      end

      # Powerful Alchemy: a save an item's note asks for is told at its maker's class DC where that is
      # higher than the DC the note gives. The game doesn't roll an item's save itself - the GM does, from
      # the note - so the note's DC is where the stamp shows.
      DC_IN_TEXT = /\bDC (\d+)/

      def self.at_makers_dc(notes, maker_dc)
        return notes unless maker_dc.to_i.positive?

        Array(notes).map do |note|
          text = note['text'].to_s.gsub(DC_IN_TEXT) { "DC #{[ Regexp.last_match(1).to_i, maker_dc.to_i ].max}" }

          note.merge('text' => text)
        end
      end

      # Quick Alchemy's limit: an effect from an item it made that would last longer than 10 minutes lasts
      # 10 minutes instead (Player Core 2, p. 59). Answers the duration to apply it with, or nil to leave
      # the effect's own. An affliction, such as a slow-acting poison, is Paizo's exception, and afflictions
      # don't come through here.
      QUICK_CAP = { 'unit' => 'minutes', 'value' => 10 }.freeze
      QUICK_CAP_ROUNDS = 100

      def self.quick_cap(effect_name, made_by)
        return nil unless made_by.to_s == Alchemy::QUICK

        duration = ActiveEffects.info(effect_name.to_s)['duration'] || {}
        unit = ActiveEffects::UNITS[duration['unit'].to_s]

        longer = if unit && unit['rounds']
                   unit['rounds'] * duration['value'].to_i > QUICK_CAP_ROUNDS
                 else
                   %w{days unlimited}.include?(duration['unit'].to_s)
                 end

        longer ? QUICK_CAP : nil
      end

      # `most` heals the highest the dice could roll.
      def self.heal(target, name, entry, out, most: false)
        unless heals?(target.holder, entry['heal_type'])
          out['lines'] << Telling.event('pf2e.consumable_no_effect', 'item' => name, 'target' => target.label)
          return
        end

        amount = most ? highest(entry['heal']) : Pf2e.roll_formula(entry['heal'])
        Harm.heal(target.holder, amount)

        out['lines'] << Telling.event('pf2e.consumable_heals', 'target' => target.label, 'count' => amount,
                                                               'item' => name)
        out['gm'] << Telling.event('pf2e.act_hp_left', 'target' => target.label, 'hp' => Harm.hit_points(target.holder))
      end

      # `origin` is the item that left it, so its rules can tell which item that was: Effect: Antidote is
      # one effect for all four antidotes, and its bonus is the one the antidote taken gives.
      def self.effect(encounter, given_by, target, name, out, origin = nil, lasts: nil)
        return unless ActiveEffects.catalogue.key?(name)

        applied = ActiveEffects.apply(target.holder, name, :applied_by => given_by, :encounter => encounter,
                                                           :origin => origin, :lasts => lasts)

        return unless applied.ok?

        out['lines'] << Telling.event('pf2e.consumable_effect', 'target' => target.label, 'effect' => name)
      end

      def self.item_origin(name, entry)
        ActiveEffects.origin(item: { 'name' => name, 'type' => 'consumable', 'level' => entry['level'],
                                     'traits' => Array(entry['traits']) })
      end

      # Vitality heals the living and does nothing for whoever has void healing, the undead and a Dar;
      # void the reverse; untyped either.
      def self.heals?(holder, type)
        void_healing = Effects.void_healing?(Effects.facts(holder))

        case type.to_s
        when 'vitality' then !void_healing
        when 'void' then void_healing
        else true
        end
      end

      # ------------------------------------------------------------------------------
      # Bombs

      # A bomb's damage beyond its own dice, as the rows `Damage` adds up: its persistent damage, which a
      # critical hit doubles with the rest, and its splash, which it never doubles.
      def self.bomb_rows(attack)
        return [ [], [] ] unless attack['bomb'] && attack['consumable']

        dice = []
        flat = []
        persistent = attack['persistent'].to_s

        if (rolled = persistent.match(/\A(\d+)d(\d+)\z/))
          dice << { 'source' => attack['name'], 'dice' => rolled[1].to_i, 'die' => "d#{rolled[2]}",
                    'damage_type' => attack['persistent_type'], 'category' => 'persistent', 'critical' => nil }
        elsif persistent.to_i.positive?
          flat << { 'source' => attack['name'], 'value' => persistent.to_i, 'damage_type' => attack['persistent_type'],
                    'category' => 'persistent', 'critical' => nil, 'creates' => true }
        end

        if attack['splash'].to_i.positive?
          flat << { 'source' => attack['name'], 'value' => attack['splash'].to_i, 'damage_type' => attack['damage_type'],
                    'category' => 'splash', 'critical' => false, 'creates' => true }
        end

        [ dice, flat ]
      end

      # One thrown: the holder's copy has one fewer, and none once the last is gone.
      def self.spend!(holder, id)
        item = Pf2egear::Inventory.held(holder, 'consumables').find { |one| one.id.to_s == id.to_s }

        return unless item

        item.quantity.to_i > 1 ? item.update(:quantity => item.quantity.to_i - 1) : item.delete
      end
    end
  end
end
