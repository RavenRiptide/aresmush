module AresMUSH
  module Pf2e

    # An antimagic rune's reaction: when a spell targets the wearer or includes them in its area, the armor
    # tries to counteract it with a 7th-rank dispel magic and a +26 counteract modifier (GM Core).
    #
    # The game has already resolved the spell by the time anyone can answer it, so what the wearer was before
    # it landed is kept, and a counteract that ends the spell puts that back: their hit points, conditions and
    # persistent damage, and the effects it put on them. It is offered only while nothing has touched their
    # hit points since, as Nimble Dodge is.
    module AntimagicRune

      NAME = 'Antimagic Armor'.freeze
      MODIFIER = 26
      RANK = 7

      # What someone wearing the rune is before a spell lands on them; nil for anyone else.
      def self.before(holder)
        return nil unless RuneActions.grants?(holder, NAME)

        damage, temp_hp = AttackAnswers.standing(holder)

        { 'damage' => damage, 'temp_hp' => temp_hp, 'conditions' => holder.pf2_conditions || {},
          'persistent' => Array(holder.pf2_persistent), 'effects' => ActiveEffects.on(holder).map { |one| one.id.to_s } }
      end

      # The spell has landed: what it was, and what they were before it, kept for the reaction, which is
      # offered while their reaction is ready.
      def self.after(target, spell, rank, dc, before, out)
        return unless before

        holder = target.holder
        TurnState.write(holder, 'spelled' => { 'spell' => spell, 'rank' => rank.to_i, 'dc' => dc, 'before' => before,
                                               'after' => AttackAnswers.standing(holder) })

        return if TurnState.turn(holder)['reaction']

        out['lines'] << Telling.event('pf2e.act_follow_up', :effect => NAME, :command => "e/act #{NAME.downcase}")
      end

      def self.act(scene, said, out)
        holder = scene.actor.holder
        spelled = TurnState.of(holder)['spelled']

        return Err.new(:no_spell, 'pf2e.antimagic_no_spell') unless spelled
        return Err.new(:too_late, 'pf2e.antimagic_too_late') unless spelled['after'] == AttackAnswers.standing(holder)

        dc = spelled['dc'] || said['dc']

        return Err.new(:needs_dc, 'pf2e.antimagic_needs_dc', 'spell' => spelled['spell']) unless dc

        rolled = Counteract.roll(MODIFIER, dc)

        out['lines'] << Telling.event('pf2e.act_announced', :actor => scene.actor.label, :action => NAME, :cost => Actions.cost(NAME),
                                                           :target => Telling.event('pf2e.antimagic_against', :spell => spelled['spell']))
        out['lines'] << Telling.event('pf2e.rune_counteract_roll', :die => rolled['die'], :modifier => MODIFIER,
                                                                  :total => rolled['total'], :rank => RANK)
        out['lines'] << RuneActions.counteract_outcome(RANK, rolled, spelled['rank'])
        TurnState.write(holder, 'spelled' => nil)

        return nil unless Counteract.ends?(RANK, rolled['degree'], spelled['rank'])

        undo!(holder, spelled['before'])
        out['lines'] << Telling.event('pf2e.antimagic_undone', :target => scene.actor.label, :spell => spelled['spell'])
        out['gm'] << Telling.event('pf2e.act_hp_left', :target => scene.actor.label, :hp => Harm.hit_points(holder))
        nil
      end

      # What the spell did, taken back: what they stood at, and the effects it brought.
      def self.undo!(holder, before)
        AttackAnswers.put_back(holder, before)

        ActiveEffects.on(holder).reject { |one| Array(before['effects']).include?(one.id.to_s) }.each do |effect|
          ActiveEffects.remove(holder, effect) if Pf2eEffect[effect.id]
        end
      end
    end
  end
end
