module AresMUSH
  module Pf2e
    module Chargen

      # Language picks.
      #
      # A pick takes one of the character's open language slots (staged in
      # state['to_assign']['open languages']) and grants the language. Taking it back frees
      # the slot and revokes that grant - the ledger keeps the row, marked reverted, so the
      # history of a player changing their mind is still there.
      module Languages

        def self.learn(state, args)
          language = args['language']
          slots = Array(state['to_assign']['open languages']).dup

          available = selectable(state)

          return refusal(state, language) unless available.any? { |l| l.casecmp?(language.to_s) }

          return Err.new(:cannot_assign, 'pf2e.cannot_assign_type', 'element' => 'language') if state['to_assign']['open languages'].nil?

          canonical = available.find { |l| l.casecmp?(language.to_s) }

          return Err.new(:already_has, 'pf2e.already_has', 'item' => 'language') if known?(state, canonical)

          index = slots.index('open')

          return Err.new(:no_free, 'pf2e.no_free', 'element' => 'language selections') if index.nil?

          slots[index] = canonical
          to_assign = state['to_assign'].merge('open languages' => slots)

          Ok.new(:state => state.merge('to_assign' => to_assign))
            .with_grant('add_language', { 'language' => canonical }, { 'effective_level' => 1 })
            .with_message('pf2e.add_ok', 'item' => canonical, 'list' => 'languages')
        end

        def self.forget(state, args)
          language = args['language']

          return Err.new(:cannot_assign, 'pf2e.cannot_assign_type', 'element' => 'language') if state['to_assign']['open languages'].nil?

          slots = Array(state['to_assign']['open languages']).dup
          index = slots.index { |s| s.is_a?(String) && s.casecmp?(language.to_s) }

          # A language from an ancestry, heritage or background is not in the player's slots
          # and is not theirs to drop.
          return Err.new(:not_in_list, 'pf2e.not_in_list', 'option' => language) if index.nil?

          canonical = slots[index]
          slots[index] = 'open'
          to_assign = state['to_assign'].merge('open languages' => slots)

          Ok.new(:state => state.merge('to_assign' => to_assign))
            .with_revocation('add_language', 'language' => canonical)
            .with_message('pf2e.reset_ok', 'option' => canonical, 'element' => 'language')
        end

        # The languages a player may choose: every language in the rarity buckets listed by
        # pf2e.can_select_language, so rare and secret ones are not offered.
        def self.selectable(state)
          config = state['config']
          buckets = Array(config.read('pf2e', 'can_select_language'))

          buckets.flat_map { |bucket| (config.read('pf2e_languages', bucket) || {}).keys }
        end

        # Why a name is not one the player may choose: there is no such language, or it is in a
        # group they cannot select. Chargen and a level-up both answer with this. It points at the
        # lang/info lists rather than naming every choice, which ran to fifty languages.
        def self.refusal(state, language)
          config = state['config']
          lists = Array(config.read('pf2e', 'can_select_language')).map { |group| "`lang/info #{group}`" }.join(' or ')

          group, names = (config.read('pf2e_languages') || {}).find do |_group, entries|
            (entries || {}).keys.any? { |l| l.casecmp?(language.to_s) }
          end

          return Err.new(:not_a_language, 'pf2e.language_not_found', 'language' => language, 'lists' => lists) unless group

          name = names.keys.find { |l| l.casecmp?(language.to_s) }
          key = group.to_s.casecmp?('rare') ? 'pf2e.language_rare_not_selectable' : 'pf2e.language_not_selectable'

          Err.new(:not_selectable, key, 'language' => name, 'group' => group, 'lists' => lists)
        end

        def self.known?(state, language)
          Array(state['sheet']['languages']).any? { |l| l.to_s.casecmp?(language.to_s) }
        end
      end
    end
  end
end
