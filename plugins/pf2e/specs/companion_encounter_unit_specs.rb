require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An animal companion's attacks as a creature's Strikes, and the messages its joining and leaving use.
    # Plain data, with no database.
    describe "an animal companion's encounter stat block" do

      before(:all) do
        @catalogue = YAML.load_file('game/config/pf2e_animal_companions.yml')['pf2e_animal_companions']
      end

      def attacks(type, companion = {})
        Companion::Stats.of({ 'type' => type }.merge(companion), :level => 1, :catalogue => @catalogue)['attacks']
      end

      it "should turn an attack into a Strike with its bonus, traits and damage" do
        jaws = attacks('Wolf').find { |one| one['name'] == 'Jaws' }
        strike = Companion::Block.strike(jaws)

        expect(strike['name']).to eq 'Jaws'
        expect(strike['bonus']).to eq jaws['bonus']
        expect(strike['traits']).to eq jaws['traits']
        expect(strike['damage']).to eq [ [ "1d8+#{jaws['modifier']}", 'piercing', nil ] ]
      end

      it "should roll an attack's additional damage as its own" do
        stinger = attacks('Scorpion').find { |one| one['name'] == 'Stinger' }

        expect(Companion::Block.strike(stinger)['damage'].last).to eq [ '1d4', 'poison', nil ]
      end

      it "should leave the modifier off damage with none" do
        strike = Companion::Block.strike('name' => 'Jaws', 'bonus' => 3, 'dice' => 1, 'die' => 'd6', 'modifier' => 0,
                                         'damage_type' => 'piercing')

        expect(strike['damage']).to eq [ [ '1d6', 'piercing', nil ] ]
      end

      it "should apply Support only for types the catalogue has, with every effect it puts on" do
        effects = YAML.load_file('game/config/pf2e_effects.yml')['pf2e_effects']
        named = Companion::Support::BENEFITS.values.flat_map { |one| [ one['effect'], one['critical'] ] }.compact + [ Companion::Support::EFFECT ]

        expect(Companion::Support::BENEFITS.keys - @catalogue['types'].keys).to eq []
        expect(named.reject { |name| effects.key?(name) }).to eq []
      end

      it "should have a row, or words to announce, for every type's maneuver, and Shred's requirement" do
        names = @catalogue['types'].values.map { |info| info['maneuver']['name'] }
        rowed = names.select { |name| Companion::Maneuvers::ROWS.key?(Domains.slug(name)) }

        expect(names - rowed).to eq [ 'Gallop' ]
        expect(@catalogue['types']['Shark']['maneuver']['description'])
          .to start_with('**Requirements** The shark hit with a jaws Strike on its most recent action this turn.')
      end

      it "should write Constrict's and Fire Breath's figures into their first lines" do
        snake = Companion::Stats.of({ 'type' => 'Snake', 'mature' => true, 'path' => 'savage' }, :level => 8, :catalogue => @catalogue)
        drake = Companion::Stats.of({ 'type' => 'Riding Drake', 'mature' => true, 'path' => 'savage' }, :level => 8, :catalogue => @catalogue)

        expect(Companion::Maneuvers.action(snake, nil)['text']).to start_with('12 bludgeoning, DC 10 basic Fortitude%r')
        breath = Companion::Maneuvers.action(drake, nil)
        expect(breath['text']).to start_with("4d6 fire, DC #{10 + 8 + 2 + drake['attributes']['Constitution']} basic Reflex%rFrequency once per hour%r")
        expect(breath['cost']).to eq 2
        expect(CreatureAbilities.frequency(breath['text'])).to eq('max' => 1, 'per' => 'hour')
      end

      it "should give a raging badger 4 more jaws damage and 2 more claw damage" do
        jaws = attacks('Badger').find { |one| one['name'] == 'Jaws' }

        expect(Companion::Block.strike(jaws, 4)['damage'].first.first).to eq "1d8+#{jaws['modifier'] + 4}"
      end

      it "should have characters and companions die as characters do, and creatures and familiars not" do
        holder = double('holder')

        expect(CharacterActor.new(holder).dies_as_character?).to be true
        expect(CompanionActor.new(holder).dies_as_character?).to be true
        expect(CreatureActor.new(holder).dies_as_character?).to be false
        expect(FamiliarActor.new(holder).dies_as_character?).to be false
        expect(CompanionActor.new(holder).hit_point_record).to equal holder
        expect(CreatureActor.new(holder).hit_point_record).to be_nil
      end

      it "should have every message its joining, leaving and view use" do
        locale = YAML.load_file('plugins/pf2e/locales/locale_en.yml')['en']['pf2e']
        keys = %w{companion_none companion_master_absent companion_encounter_untyped companion_encounter_unapproved
                  companion_encounter_dead companion_encounter_unnamed companion_encounter_here companion_encounter_clash
                  companion_encounter_absent companion_encounter_joined companion_encounter_joined_carried
                  companion_encounter_left companion_took_damage companion_took_damage_why view_kind_companion
                  view_companion_of companion_commanded companion_command_not_yours companion_command_again
                  companion_command_after_own companion_command_actions companion_command_cry companion_not_commanded
                  companion_act_only companion_no_reactions companion_own_action_only companion_turn_reminder
                  companion_turn_reminder_independent minion_not_master_turn companion_support_no_master
                  companion_support_applied companion_support_told companion_support_word_unsupported
                  companion_support_benefit companion_support_damage companion_support_effect
                  companion_support_after_action companion_support_moves_only companion_maneuver_spent
                  companion_maneuver_needs_hit companion_maneuver_moves companion_maneuver_display
                  companion_maneuver_released companion_constrict_too_big companion_raging_concentrate
                  companion_badger_cannot_rage companion_badger_rages companion_sheet_not_here
                  companion_sheet_not_companion companion_sheet_own_action companion_sheet_supporting companion_died}

        expect(keys.reject { |key| locale.key?(key) }).to eq []
        expect(locale.keys.grep(/\Acompanion_encounter_(gm_acts|not_minion)\z|\Afamiliar_not_master_turn\z/)).to eq []
      end
    end
  end
end
