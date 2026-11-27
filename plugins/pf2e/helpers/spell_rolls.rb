module AresMUSH
  module Pf2e

    # What the caster's own rules do to a spell's damage and healing as it is rolled: Healing Hands rolls
    # heal's d8s as d10s, Communal Healing reminds them of the second creature their heal may help.
    #
    # Their rules name the roll the way Foundry's do, `spell-healing` for what a spell heals and
    # `spell-damage` for what it deals, and ask which spell it is (`item:slug:heal`) and how many actions it
    # was cast with (`item:cast:actions`).
    module SpellRolls

      DIE = /d(\d+)/

      # The selector each kind of formula answers to.
      def self.domains(kinds)
        listed = Array(kinds)

        (listed.include?('healing') ? [ 'spell-healing' ] : []) + (listed.include?('damage') || !listed.include?('healing') ? [ 'spell-damage' ] : [])
      end

      def self.options(caster, spell, domains, actions)
        Effects.options(caster, domains) + [ "item:slug:#{Domains.slug(spell)}" ] +
          (actions ? [ "item:cast:actions:#{actions.to_i}" ] : [])
      end

      # The formulas, `[ formula, type, category, kinds ]`, with a die size the caster's rules override.
      def self.dice(caster, spell, formulas, actions = nil)
        return formulas if Actors.of(caster).creature?

        sources = Effects.sources(caster)

        formulas.map do |formula, *rest|
          domains = domains(rest[2])
          held = options(caster, spell, domains, actions)
          size = Rules.gather(sources, domains, held, 'DamageDice') { |row, _source| row }
                      .map { |row| (row['override'] || {})['dieSize'] }.compact.last

          [ size ? formula.to_s.gsub(DIE, size) : formula, *rest ]
        end
      end

      # The words of the caster's notes on what the spell heals or deals.
      def self.notes(caster, spell, formulas, actions = nil)
        return [] if Actors.of(caster).creature?

        domains = formulas.flat_map { |_formula, *rest| domains(rest[2]) }.uniq

        Rules.notes(Effects.sources(caster), domains, options(caster, spell, domains, actions))
             .map { |note| note['text'].to_s }.reject(&:empty?).uniq
      end
    end
  end
end
