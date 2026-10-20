module AresMUSH
  module Pf2e

    # A creature's stat block as text, the way a GM reads one at the table.
    module StatBlock

      # `Ranged Javelin +6 (thrown-30), 1d6+4 piercing plus Grab`: a Strike with a range increment is
      # ranged, and what it deals is its damage and then what else a hit does.
      def self.strike_line(strike, block = {})
        traits = Array(strike['traits'])
        ranged = Npcs.range_of(strike).positive?
        hits = Array(strike['damage']).map { |formula, type, category| [ formula, category, type == 'untyped' ? nil : type ].compact.join(' ') } +
               Array(strike['effects'])

        "#{ranged ? 'Ranged' : 'Melee'} #{strike['name']} #{signed(strike['bonus'])}" \
          "#{traits.any? ? " (#{traits.join(', ')})" : ''}#{hits.any? ? ", #{hits.join(' plus ')}" : ''}" \
          "#{strike['when'] ? "; #{Shapes.when_words(block, strike['when'])}" : ''}"
      end

      def self.lines(name, block, npc: nil, gm: true)
        lines = [ "%xh#{name}%xn  #{block['adjustment'] ? "#{block['adjustment'].capitalize} " : ''}Creature #{block['level']}  #{traits(block)}" ]

        if npc
          conditions = Pf2e.condition_labels(npc, false)
          lines << "#{t('pf2e.creature_hp')}: #{gm ? Harm.hit_points(npc) : t('pf2e.creature_hp_hidden')}" \
                   "#{conditions.empty? ? '' : "  #{t('pf2e.creature_conditions')}: #{conditions.join(', ')}"}"
          effects = ActiveEffects.on(npc).map(&:name)
          lines << "#{t('pf2e.creature_effects')}: #{effects.join(', ')}" if effects.any?
          shapes = gm ? Shapes.shown(npc) : []
          lines << shapes.join('; ') if shapes.any?
        end

        return lines unless gm

        lines << "Perception #{signed(block['perception'])}#{senses(block)}"
        lines << "Skills #{(block['skills'] || {}).map { |skill, value| "#{skill} #{signed(value)}" }.join(', ')}" if block['skills']
        lines << "AC #{block['ac']}; Fort #{signed(saves(block, 'fortitude'))}, Ref #{signed(saves(block, 'reflex'))}, " \
                 "Will #{signed(saves(block, 'will'))}"
        lines << "HP #{block['hp']}#{block['hp_details'] ? " (#{block['hp_details']})" : ''}" \
                 "#{block['hardness'].to_i.positive? ? ", Hardness #{block['hardness']}" : ''}#{iwr(block)}"
        lines << shield_line(block['shield'], npc) if block['shield']
        lines << t('pf2e.creature_starts_as', :shape => block['shape']) if block['shape']
        lines << "Speed #{block['speeds'].map { |kind, feet| kind == 'land' ? "#{feet} feet" : "#{kind} #{feet} feet" }.join(', ')}" if Hash(block['speeds']).any?

        Array(block['strikes']).each { |strike| lines << strike_line(strike, block) }

        Array(block['spellcasting']).each do |casting|
          spells = (casting['spells'] || {}).map { |rank, names| "#{rank_words(casting, rank)}: #{spell_words(casting, names)}" }
          lines << "#{casting['name']} DC #{casting['dc']}, attack #{signed(casting['attack'])}; #{spells.join('; ')}"
        end

        Array(block['actions']).each do |ability|
          cost = ability['type'] == 'action' ? "[#{ability['cost'] || 1}]" : "[#{ability['type']}]"
          lines << "%xh#{ability['name']}%xn #{cost} #{brief(ability['text'])}"
        end

        lines
      end

      # `Rank 4 (3 slots)` for a spontaneous caster's.
      def self.rank_words(casting, rank)
        return 'Cantrips' if rank.to_s == '0'

        slots = (casting['slots'] || {})[rank.to_s]

        "Rank #{rank}#{slots ? " (#{slots} slots)" : ''}"
      end

      # A rank's spells, one prepared more than once or cast more than once a day saying how often.
      def self.spell_words(casting, names)
        names.tally.map do |name, count|
          times = [ count, (casting['uses'] || {})[name].to_i ].max

          times > 1 ? "#{name} (x#{times})" : name
        end.join(', ')
      end

      # `Shield Wooden Shield +2 (Hardness 3, HP 8 / 12, BT 6)`, with what the creature's own has left.
      def self.shield_line(shield, npc = nil)
        left = npc ? "#{[ shield['hp'].to_i - npc.shield_damage.to_i, 0 ].max} / " : ''

        "Shield #{shield['name']} #{signed(shield['ac'])} (Hardness #{shield['hardness']}, HP #{left}#{shield['hp']}, " \
          "BT #{shield['hp'].to_i / 2})"
      end

      def self.signed(value)
        value.to_i.negative? ? value.to_s : "+#{value.to_i}"
      end

      # An ability's words at a stat block's length. Using the ability tells all of them.
      BRIEF = 400

      def self.brief(text)
        text = text.to_s

        text.length > BRIEF ? "#{text[0, BRIEF].rpartition(' ').first}…" : text
      end

      def self.saves(block, name)
        (block['saves'] || {})[name]
      end

      def self.traits(block)
        ([ block['rarity'] == 'common' ? nil : block['rarity'], block['size'] ] + Array(block['traits'])).compact
                                                                                         .map(&:capitalize).join(', ')
      end

      def self.senses(block)
        Array(block['senses']).empty? ? '' : "; #{block['senses'].join(', ')}"
      end

      def self.iwr(block)
        parts = []
        parts << "Immunities #{Npcs.immunities(block).join(', ')}" if Npcs.immunities(block).any?
        parts << "Weaknesses #{Npcs.listed_words(block['weaknesses']).join(', ')}" if block['weaknesses']
        parts << "Resistances #{Npcs.listed_words(block['resistances']).join(', ')}" if block['resistances']

        parts.empty? ? '' : "; #{parts.join('; ')}"
      end
    end

    # `+e/creature <#id|name|creature>` - a combatant's stat block and state, or a creature from the
    # bestiary or a saved one. Players in an encounter see a combatant's name and conditions; its GM sees
    # the whole block, and reads the bestiary and the saved creatures they may see.
    class PF2EncounterCreatureCmd
      include CommandHandler

      attr_accessor :term

      def parse_args
        self.term = trim_arg(cmd.args)
      end

      def required_args
        [ self.term ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        gm = encounter ? Combatants.gm?(enactor, encounter) : true

        if encounter
          found = Combatants.find(encounter, self.term)

          if found.ok? && found.state.creature?
            npc = found.state.holder
            return client.emit(StatBlock.lines(npc.name, npc.stat_block, :npc => npc, :gm => gm).join('%r'))
          end
        end

        # A stat block is for whoever runs the fight. Someone in another's reads it when it is over.
        return client.emit_failure(t('pf2e.creature_gm_only')) unless gm

        found = Creatures.find(enactor, self.term, 'view')

        return if CharState.emit_error!(client, found)

        client.emit StatBlock.lines(found.state['name'], Creatures.shown_block(enactor, found.state)).join('%r')
      end
    end

    # `+e/bestiary <words>[/<level>]` - creatures whose names hold the words: the bestiary's this
    # character may add, then the saved ones they may use, each with whose it is.
    class PF2EncounterBestiaryCmd
      include CommandHandler

      attr_accessor :words, :level

      LIMIT = 40

      def parse_args
        words, _, level = cmd.args.to_s.partition('/')
        self.words = words.strip
        self.level = level.strip.match?(/\A-?\d+\z/) ? level.strip.to_i : nil
      end

      def required_args
        [ self.words ]
      end

      def handle
        found = Bestiary.search(self.words, self.level).select { |name, _one| Gm.open?(enactor, name) }
                        .map { |name, one| "#{name.ljust(40)} Creature #{one['level']}" }
        found += saved.map do |creature|
          "#{"c:#{creature.id} #{creature.name}".ljust(40)} Creature #{creature.level} [#{whose(creature)}]"
        end

        return client.emit_failure(t('pf2e.creature_not_found', :creature => self.words)) if found.empty?

        lines = found.first(LIMIT)
        lines << t('pf2e.bestiary_more', :count => found.size - LIMIT) if found.size > LIMIT

        client.emit lines.join('%r')
      end

      def saved
        wanted = Domains.slug(self.words)

        Creatures.allowed(enactor, 'use').select { |creature| creature.name_slug.to_s.include?(wanted) }
                 .select { |creature| self.level.nil? || creature.level.to_i == self.level }.sort_by { |creature| [ creature.level.to_i, creature.name ] }
      end

      def whose(creature)
        return 'yours' if creature.owner_id.to_s == enactor.id.to_s

        creature.published_id ? 'published' : creature.owner_name
      end
    end

    # `+e/add [<count>] [elite|weak] <creature>[/<shape>][=<name>]` adds creatures from the bestiary, or
    # saved ones, to the encounter, each with its own id and initiative, adjusted if the GM says so, and
    # in the shape named, if it has one (`Shapes`). A saved one
    # is added as the revision the GM gets (`Creatures`), which no later edit changes.
    # `+e/add [elite|weak] <name>=<description>` adds one of the GM's own making (`Pf2e::Described`),
    # which is a Plotmaster's or staff's to do.
    class PF2EncounterAddCmd
      include CommandHandler

      attr_accessor :count, :adjustment, :creature, :name, :shape

      def parse_args
        left, _, right = cmd.args.to_s.partition('=')
        found = left.strip.match(/\A(?:(?<count>\d+)\s+)?(?:(?<adjustment>#{Adjustments.names.join('|')})\s+)?(?<creature>.+)\z/i)

        self.count = found && found[:count] ? found[:count].to_i.clamp(1, 20) : 1
        self.adjustment = found && found[:adjustment] ? found[:adjustment].downcase : nil
        self.creature = found ? found[:creature].strip : left.strip
        self.creature, _, shape = self.creature.partition('/')
        self.creature = self.creature.strip
        self.shape = shape.strip.empty? ? nil : shape.strip
        self.name = right.strip
      end

      def required_args
        [ self.creature ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter

        cannot = Pf2e.can_modify_encounter(enactor, encounter)

        return client.emit_failure(cannot) if cannot

        # A creature the bestiary itself calls elite or weak is that creature, as written.
        if self.adjustment && Bestiary.named("#{self.adjustment} #{self.creature}")
          self.creature = "#{self.adjustment} #{self.creature}"
          self.adjustment = nil
        end

        described = Described.read(self.creature, self.name)

        return client.emit_failure(t('pf2e.creature_custom_not_open')) if described && !Gm.plotmaster?(enactor)
        return if described && CharState.emit_error!(client, described)
        return if described && CharState.emit_error!(client, shape_of(self.creature, described.state))

        added = if described
                  [ Combatants.add_npc(encounter, :described => described.state, :adjustment => self.adjustment) ]
                else
                  found = Creatures.find(enactor, self.creature, 'use')
                  return if CharState.emit_error!(client, found)

                  ref = found.state
                  unless Creatures.usable?(enactor, ref)
                    return client.emit_failure(t(ref['source'] == 'saved' ? 'pf2e.creature_saved_not_open' : 'pf2e.creature_not_open', :creature => ref['name']))
                  end

                  return if CharState.emit_error!(client, shape_of(ref['name'], Creatures.block(ref)))

                  from = ref['source'] == 'saved' ? { :revision => ref['revision'] } : { :creature => ref['name'] }

                  self.count.times.map do |index|
                    named = self.name.empty? ? nil : (self.count > 1 ? "#{self.name} #{index + 1}" : self.name)
                    Combatants.add_npc(encounter, **from, :name => named, :adjustment => self.adjustment)
                  end
                end

        # In the shape the GM named, or the one a saved creature was saved to start in.
        added.each do |one|
          shape = self.shape || one.state['npc'].stat_block['shape']
          Shapes.take!(one.state['npc'], shape) if shape
        end

        added.each do |one|
          npc = one.state['npc']
          named = npc.name.end_with?("##{npc.number}") ? npc.name : "#{npc.name} (##{npc.number})"
          message = t('pf2e.encounter_add_ok', :roll => one.state['initiative'], :encounter => encounter.id,
                                               :name => named)
          Pf2e::Encounters::Announce.tell(encounter, message, :room => enactor_room)
        end
      end

      # Refused where it was asked to start in a shape its stat block does not give it.
      def shape_of(name, block)
        return Ok.new(:state => nil) if self.shape.nil? || Shapes.choices_in(block).any? { |one| Domains.slug(one) == Domains.slug(self.shape) }

        Err.new(:no_shape, 'pf2e.shape_unknown', 'creature' => name, 'shape' => self.shape, 'shapes' => Shapes.choices_in(block).join(', '))
      end
    end

    # `+e/adjust <#id>[,<#id>...]=elite|weak|normal` - makes a creature already in the encounter elite or
    # weak, or takes the adjustment off. It keeps the hit points it has lost. The GM is told; the room is
    # not, because what a creature is made of is the GM's to know.
    class PF2EncounterAdjustCmd
      include CommandHandler

      attr_accessor :targets, :word

      def parse_args
        left, _, right = cmd.args.to_s.partition('=')

        self.targets = left.split(',').map(&:strip).reject(&:empty?)
        self.word = right.strip
      end

      def required_args
        [ self.targets.first, self.word ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter

        cannot = Pf2e.can_modify_encounter(enactor, encounter)

        return client.emit_failure(cannot) if cannot

        adjustment = Adjustments.named(self.word)

        if adjustment == :unknown
          return client.emit_failure(t('pf2e.adjust_unknown', :adjustment => self.word,
                                                             :options => (Adjustments.names + [ Adjustments::NONE.first ]).join(', ')))
        end

        found = self.targets.map { |term| Combatants.find(encounter, term) }
        failed = found.find(&:err?)

        return if failed && CharState.emit_error!(client, failed)

        adjusted = found.map(&:state)
        character = adjusted.find { |one| !one.creature? }

        return client.emit_failure(t('pf2e.adjust_not_creature', :who => character.label)) if character

        adjusted.each { |one| one.holder.adjust(adjustment) }

        client.emit_success t('pf2e.adjust_ok', :who => adjusted.map(&:label).join(', '),
                                                :adjustment => adjustment || Adjustments::NONE.first)
      end
    end
  end
end
