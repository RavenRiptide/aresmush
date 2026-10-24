module AresMUSH
  module Pf2e

    # Where a creature's figures sit for its level, by GM Core's tables for building creatures
    # (`game/config/pf2e_creature_benchmarks.yml`, transcribed by `scripts/import_creature_benchmarks.py`).
    #
    # A band is the book's column a figure reaches: extreme, high, moderate, low, terrible. A figure past
    # the top of the highest is "above extreme", and is flagged to its author and to the admins who
    # approve it, who judge it (Raven, 2026-10-14); nothing is refused for it.
    module CreatureBenchmarks

      def self.tables
        Global.read_config('pf2e_creature_benchmarks') || {}
      end

      # The top of a cell: a figure, the high end of a range, or a damage's average.
      def self.top(cell)
        case cell
        when Array then cell.first
        when Hash then cell['average']
        else cell
        end
      end

      # The bottom of a cell, where a figure reaches that band.
      def self.bottom(cell)
        cell.is_a?(Array) ? cell.last : top(cell)
      end

      def self.cells(kind, level)
        table = tables[kind] || {}
        held = table['levels'] || {}

        # A creature past the levels the book's tables give is not weighed against the nearest.
        [ Array(table['columns']), held[level.to_i] || [] ]
      end

      def self.band(kind, level, value)
        columns, cells = cells(kind, level)
        listed = columns.zip(cells).reject { |_column, cell| cell.nil? }

        return nil if listed.empty?
        return "above #{spaced(listed.first.first)}" if value > top(listed.first.last)

        found = listed.find { |_column, cell| value >= bottom(cell) }

        found ? spaced(found.first) : "below #{spaced(listed.last.first)}"
      end

      def self.spaced(column)
        column.to_s.tr('_', ' ')
      end

      # Each figure with its band: `{ 'figure', 'value', 'band' }`.
      def self.bands(block)
        level = block['level'].to_i
        placed = [ [ 'AC', 'ac', block['ac'] ], [ 'Hit Points', 'hp', block['hp'] ], [ 'Perception', 'perception', block['perception'] ] ]
        placed += %w{fortitude reflex will}.map { |save| [ save.capitalize, 'save', Hash(block['saves'])[save] ] }
        placed += Hash(block['skills']).map { |skill, value| [ skill, 'skill', value ] }
        placed += Array(block['strikes']).flat_map do |strike|
          damage = Array(strike['damage']).sum { |formula, _type, _category| Pf2e.average(formula).to_i }
          [ [ "#{strike['name']} attack", 'strike_attack', strike['bonus'] ], [ "#{strike['name']} damage", 'strike_damage', damage ] ]
        end
        placed += Array(block['actions']).filter_map do |ability|
          dealt = CreatureAbilities.damage_save(ability['text'])
          next nil unless dealt

          # Used every round it may be, however its frequency is written, it is unlimited.
          often = CreatureAbilities.frequency(ability['text'])
          limited = Recharge.rounds_of(ability['name'], ability) || (often && !%w{round turn}.include?(often['per']))
          [ "#{ability['name']} damage", 'area_damage', Pf2e.average(dealt['formula']).to_i, limited ? 'limited_use' : 'unlimited_use' ]
        end

        placed.filter_map do |figure, kind, value, column|
          next nil if value.nil?

          band = column ? one_column(kind, level, value.to_i, column) : band(kind, level, value.to_i)
          band && { 'figure' => figure, 'value' => value.to_i, 'band' => band }
        end
      end

      # Against a single column - area damage, limited or not: within it, or above it.
      def self.one_column(kind, level, value, column)
        columns, cells = cells(kind, level)
        cell = cells[columns.index(column).to_i]

        return nil if cell.nil?

        value > top(cell) ? "above #{spaced(column)}" : spaced(column)
      end

      def self.warnings(block)
        bands(block).select { |one| one['band'].start_with?('above') }.map do |one|
          CreatureCheck.found(:creature_above, 'figure' => one['figure'], 'value' => one['value'], 'level' => block['level'].to_i, 'band' => one['band'])
        end
      end

      # ------------------------------------------------------------------------------
      # Road maps

      # GM Core's base road maps, a brute and a sniper and the rest, each with the band of the figures it
      # names and its own words (`game/config/pf2e_creature_road_maps.yml`).
      def self.road_maps
        Global.read_config('pf2e_creature_road_maps') || {}
      end

      def self.road_map(name)
        road_maps.find { |key, _held| key.casecmp?(name.to_s.strip) }
      end

      ATTRIBUTES = %w{str dex con int wis cha}.freeze
      SAVES = %w{fortitude reflex will}.freeze

      # A creature to start from: every figure at the band its road map gives it, and moderate where it
      # gives none, as the book says; the middle of a hit point range; one Strike, and spells' DC and attack
      # where the road map names them, for the author to fill in and rename.
      def self.starting(level, name)
        found = road_map(name)
        return Err.new(:road_map_unknown, 'pf2e.road_map_unknown', 'name' => name, 'road_maps' => road_maps.keys.join(', ')) unless found

        levels = Hash(tables.dig('ac', 'levels')).keys.map(&:to_i)
        return Err.new(:road_map_level, 'pf2e.road_map_level', 'from' => levels.min, 'to' => levels.max) unless levels.include?(level.to_i)

        level = level.to_i
        bands = Hash(found.last['bands'])
        at = ->(figure, kind = figure) { figure_at(kind, level, bands[figure] || 'moderate') }

        block = { 'name' => '', 'level' => level, 'size' => 'medium', 'traits' => [], 'ac' => at.call('ac'), 'hp' => at.call('hp'),
                  'perception' => at.call('perception'),
                  'saves' => SAVES.to_h { |save| [ save, at.call("save.#{save}", 'save') ] },
                  'abilities' => ATTRIBUTES.to_h { |one| [ one, at.call("attribute.#{one}", 'attribute') ] },
                  'strikes' => [ strike(level, bands) ], 'actions' => [] }

        block['spellcasting'] = [ spells(level, bands['spell']) ] if bands['spell']

        Ok.new(:state => block)
      end

      # A figure at a band: its number, the middle of a range, or a damage's formula. A band the book leaves
      # empty at that level is read as moderate.
      def self.figure_at(kind, level, band)
        columns, cells = cells(kind, level)
        cell = cells[columns.index(band)] if columns.include?(band)
        cell = cells[columns.index('moderate')] if cell.nil? && columns.include?('moderate')

        case cell
        when Array then ((cell.first + cell.last) / 2.0).round
        when Hash then cell['formula']
        else cell
        end
      end

      def self.strike(level, bands)
        ranged = bands['ranged'] ? true : false
        strike = { 'name' => ranged ? 'Ranged Strike' : 'Strike', 'bonus' => figure_at('strike_attack', level, bands['strike_attack'] || 'moderate'),
                   'damage' => [ [ figure_at('strike_damage', level, bands['strike_damage'] || 'moderate'), ranged ? 'piercing' : 'bludgeoning', nil ] ],
                   'traits' => [] }

        ranged ? strike.merge('range' => 60) : strike
      end

      def self.spells(level, band)
        { 'name' => 'Spells', 'tradition' => 'arcane', 'type' => 'innate', 'dc' => figure_at('spell', level, "#{band}_dc"),
          'attack' => figure_at('spell', level, "#{band}_spell_attack_bonus"), 'spells' => {} }
      end
    end
  end
end
