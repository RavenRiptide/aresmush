module AresMUSH
  module Pf2e

    # An encounter's table, in turn order: everyone's figures, and beneath each row what they are under,
    # how long each effect on them lasts, their cover, and what they shrug off or are hurt more by. Whoever
    # isn't the encounter's GM sees a creature's figures as `?` and its hit points as how hurt it looks.
    class PF2EncounterViewTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :encounter

      REACTIVE_STRIKE = 'Reactive Strike'.freeze
      HIDDEN = '?'.freeze

      # A row's figures, by who it is a row for.
      CHARACTER = {
        'kind' => ->(char) { char.pf2_base_info['charclass'] },
        'hp' => ->(char) { Pf2eHP.display_character_hp(char) },
        'ac' => ->(char) { Pf2eCombat.calculate_ac(char) },
        'perception' => ->(char) { Pf2eCombat.get_perception(char) },
        'save' => ->(char, save) { Pf2eCombat.get_save_bonus(char, save) },
        'reactive' => ->(char) { Actions.owned?(char, REACTIVE_STRIKE) },
        'iwr' => ->(char) { IWR.of(char) }
      }.freeze

      CREATURE = {
        'kind' => ->(npc) { "#{(npc.stat_block['adjustment'] || 'creature').capitalize} #{npc.stat_block['level']}" },
        'hp' => ->(npc) { Pf2eHP.display_hp(npc.hp_left, npc.max_hp) },
        'ac' => ->(npc) { Npcs.stat(npc, 'ac')['total'] },
        'perception' => ->(npc) { Npcs.stat(npc, 'perception')['total'] },
        'save' => ->(npc, save) { Npcs.stat(npc, 'save', save)['total'] },
        'reactive' => ->(npc) { Array(npc.stat_block['actions']).any? { |one| one['name'] == REACTIVE_STRIKE } },
        'iwr' => ->(npc) { Npcs.iwr(npc) }
      }.freeze

      SAVES = %w{fortitude reflex will}.freeze

      IWR_WORDS = { 'immunity' => 'Immune', 'weakness' => 'Weak', 'resistance' => 'Resist' }.freeze

      def initialize(encounter, client, viewer)
        @encounter = encounter
        @client = client
        @viewer = viewer

        super File.dirname(__FILE__) + "/encounter_view.erb"
      end

      def title
        t(exploring? ? 'pf2e.exploration_view_title' : 'pf2e.initiative_view_title', :id => @encounter.id)
      end

      # An exploration has no initiative; the line beneath each row says what they are doing instead.
      def exploring?
        Pf2e::Exploration.exploring?(@encounter)
      end

      def gm?
        @gm = Combatants.gm?(@viewer, @encounter) if @gm.nil?
        @gm
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      # Widths of the figures after the name; a save's heading is as wide as its column allows.
      SAVE_WIDTHS = [ 5, 4, 5 ].freeze

      def header_line
        "#{item_color}#{left("#", 4)}#{left("Init", 5)}#{left("Name", 15)}%b#{left("Kind", 12)}%b#{left("HP", 15)}%b" \
          "#{left("AC", 3)}%b#{left("Per", 4)}#{%w{Fort Ref Will}.zip(SAVE_WIDTHS).map { |name, width| left(name, width) }.join}" \
          "#{left("RS", 2)}%xn"
      end

      # Everyone in the order: a row each, and a line beneath it where there is anything to say.
      def combatant_list
        Combatants.all(@encounter).flat_map do |one|
          next [ row(one) ] unless one.holder

          # One read block per combatant, because the figures all ask the same questions about the same one.
          AresMUSH::Pf2e::SheetReads.holding(one.holder) { [ row(one), beneath(one) ].compact }
        end
      end

      def row(one)
        # The id has its own column, so a name that ends with it is shown without.
        name = one.label.sub(/ #{Regexp.escape(one.ref)}\z/, '')
        start = "#{left(one.ref, 4)}#{left(exploring? ? '-' : one.init.to_i, 5)}#{left(name, 15)}"

        return start unless one.holder

        shown = figures(one)
        saves = shown['saves'].zip(SAVE_WIDTHS).map { |save, width| left(save, width) }.join

        "#{start}%b#{left(shown['kind'], 12)}%b#{left(shown['hp'], 15)}%b#{left(shown['ac'], 3)}%b" \
          "#{left(shown['perception'], 4)}#{saves}#{shown['reactive']}"
      end

      # A row's figures as this viewer may see them.
      def figures(one)
        holder = one.holder

        if hidden?(one)
          return { 'kind' => HIDDEN, 'hp' => Harm.looks(holder), 'ac' => HIDDEN, 'perception' => HIDDEN,
                   'saves' => SAVES.map { HIDDEN }, 'reactive' => HIDDEN }
        end

        reads = reads_for(one)

        { 'kind' => reads['kind'].call(holder), 'hp' => reads['hp'].call(holder), 'ac' => reads['ac'].call(holder),
          'perception' => signed(reads['perception'].call(holder)),
          'saves' => SAVES.map { |save| signed(reads['save'].call(holder, save)) },
          'reactive' => reads['reactive'].call(holder) ? 'Y' : 'N' }
      end

      # A creature's figures are the GM's alone.
      def hidden?(one)
        one.creature? && !gm?
      end

      def reads_for(one)
        one.creature? ? CREATURE : CHARACTER
      end

      # `Hero Points 2; Frightened 1; Bless (2 rounds); standard cover, concealed; Immune poison`, or nothing.
      def beneath(one)
        parts = [ hero_points(one), conditions(one), effects(one), cover(one), activity(one), iwr(one) ].compact

        parts.empty? ? nil : "#{' ' * 4}#{parts.join('; ')}"
      end

      # Hero Points are a player character's, in an encounter that is part of a scene.
      def hero_points(one)
        scene = @encounter.scene
        char = one.creature? ? nil : HeroPoints.character(one.holder)

        scene && char ? t('pf2e.hero_scan', :count => HeroPoints.held(scene, char)) : nil
      end

      def conditions(one)
        joined(Pf2e.condition_labels(one.holder, false))
      end

      def effects(one)
        joined(ActiveEffects.on(one.holder).map { |effect| "#{effect.name} (#{ActiveEffects.remaining(effect)})" })
      end

      def cover(one)
        number = one.number.to_s
        cover = (@encounter.cover || {})[number]

        joined([ cover ? "#{cover} cover" : nil, (@encounter.concealment || {})[number] ].compact)
      end

      def activity(one)
        holder = one.holder
        doing = exploring? && holder.respond_to?(:exploration_activity) ? holder.exploration_activity : nil

        doing.to_s.empty? ? nil : t('pf2e.view_activity', :activity => doing)
      end

      def iwr(one)
        return nil if hidden?(one)

        joined(IWR.summary(reads_for(one)['iwr'].call(one.holder)).map { |kind, shown| "#{IWR_WORDS[kind]} #{shown.join(', ')}" }, '; ')
      end

      def joined(list, with = ', ')
        list.empty? ? nil : list.join(with)
      end

      def signed(value)
        value.to_i.negative? ? value.to_s : "+#{value.to_i}"
      end

      # For the GM, who builds the encounter by it; players are not told how hard a fight is meant to be.
      def difficulty
        exploring? || !gm? ? '' : Pf2e::Difficulty.shown(@encounter)
      end

      def page
        t('pf2e.encounter_page', :url => PF2Encounter.page_url(@encounter))
      end

      def trusted
        Array(@encounter.trusted)
      end

    end
  end
end
