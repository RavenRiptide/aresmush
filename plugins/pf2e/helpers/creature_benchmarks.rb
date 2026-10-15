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
    end
  end
end
