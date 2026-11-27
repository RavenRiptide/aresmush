module AresMUSH
  module Pf2e

    # A wizard's Drain Bonded Item: a spell they prepared today and have cast is theirs to cast again,
    # once a day. It goes back into the day's slots at the rank it was prepared at, to be cast with
    # `+e/cast` as before.
    module BondedItem

      NAME = 'Drain Bonded Item'.freeze

      def self.drain(scene, words, out)
        holder = scene.actor.holder
        magic = holder.magic
        term = Array(words).map(&:to_s).reject(&:empty?).first

        return Err.new(:name_a_spell, 'pf2e.drain_name_a_spell') unless magic && term

        found = Pf2emagic.get_spell_details(term)

        return Err.new(:no_spell, 'pf2e.drain_nothing', 'spell' => term) if found.is_a?(String)

        spell = found.first
        today = magic.spells_today || {}
        cast = cast_today(magic.spells_prepared || {}, today, spell)

        return Err.new(:not_cast, 'pf2e.drain_nothing', 'spell' => spell) unless cast

        charclass, rank = cast
        today = today.merge(charclass => today[charclass].merge(rank => Array(today[charclass][rank]) + [ spell ]))
        magic.update(:spells_today => today)

        out['lines'] << Telling.event('pf2e.drain_done', :actor => scene.actor.label, :spell => spell, :rank => rank)

        feats = Pf2emagic::CastFeats.held(holder, 'drain_bonded', charclass)
        extra_use(scene, feats, charclass, rank, out)
        linked_focus(scene, feats, charclass, rank, spell, out)

        Ok.new(:state => out)
      end

      # A feat's extra drain a day, for a spell so many ranks below the highest slot (Superior Bond). Its
      # rule raises the frequency; a later drain of a higher spell is the GM's to allow, and they are told,
      # as for any frequency.
      def self.extra_use(scene, feats, charclass, rank, out)
        holder = scene.actor.holder
        feat, block = feats.find { |_feat, one| one['extra_use_below_top'] }

        return unless feat && TurnState.used(holder, NAME) >= 1

        highest = Pf2emagic::SlotFeats.top_rank(holder, charclass) - block['extra_use_below_top'].to_i

        return if rank.to_i <= highest

        out['gm'] << Telling.event('pf2e.drain_extra_too_high', :actor => scene.actor.label, :feat => feat, :rank => rank,
                                                                :highest => highest)
      end

      # A Focus Point back, once a day, for draining to cast a curriculum spell (Linked Focus).
      def self.linked_focus(scene, feats, charclass, rank, spell, out)
        holder = scene.actor.holder
        feat = feats.find { |_feat, block| block['focus_point'].to_s == 'curriculum' }&.first

        return unless feat && TurnState.used(holder, feat).zero?
        return unless Pf2emagic.curriculum_spells(holder, charclass, rank).any? { |one| one.casecmp?(spell.to_s) }

        magic = holder.magic
        max = Pf2emagic.focus_pool_max(magic)
        current = Pf2emagic.focus_points_left(magic)

        return unless current < max

        magic.update(:focus_pool => { 'current' => current + 1 })
        TurnState.count_use(holder, feat, 'day')

        out['lines'] << Telling.event('pf2e.drain_focus_point', :actor => scene.actor.label, :feat => feat, :points => current + 1)
      end

      # The class and rank a spell was prepared at today and has been cast from: prepared there more
      # often than it is left there.
      def self.cast_today(prepared, today, spell)
        prepared.each do |charclass, ranks|
          (ranks || {}).each do |rank, spells|
            next if rank.to_s == 'cantrip'

            left = Array((today[charclass] || {})[rank]).count(spell)
            # Prepared, as the day's swaps (prepare/swap, prepare/reprepare) have changed it: a spell swapped
            # away was not cast.
            began = Pf2emagic::PreparedSwaps.expected(spells, today, charclass, rank, spell)

            return [ charclass, rank ] if began > left && today[charclass]
          end
        end

        nil
      end
    end
  end
end
