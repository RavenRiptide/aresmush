require "plugin_test_loader"
require_relative "../../pf2e/specs/support/auto_builder"

module AresMUSH
  module Pf2emagic

    # A caster's focus pool: one point for each source that grants one, capped at three.
    #
    # A grant adds its points to the pool the character already holds. The recount reaches the same
    # total from the character's class, specialty, feats and archetype specialties, which is what
    # refocus falls back on and what repairs a character whose stored maximum is wrong.
    describe "focus pool", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Pool#{rand(1000000)}")
        @magic = PF2Magic.get_create_magic_obj(@char)
      end

      after(:each) do
        @char.delete if @char
      end

      def as(charclass, specialize: nil, feats: {}, archetypes: {})
        base = @char.pf2_base_info.merge('charclass' => charclass)
        base['specialize'] = specialize if specialize

        @char.update(:pf2_base_info => base, :pf2_feats => feats,
                     :pf2_archetypeinfo => @char.pf2_archetypeinfo.merge(archetypes))
        @char = Character[@char.id]
      end

      def pool
        PF2Magic[@magic.id].focus_pool
      end

      def hold(max, current)
        @magic.update(:focus_pool => { 'max' => max, 'current' => current })
      end

      def grant(points)
        PF2Magic.update_magic(Character[@char.id], @char.pf2_base_info['charclass'], { 'focus_pool' => points }, nil)
      end

      describe "a grant" do
        # The class's own point is the grant being applied, so it is counted once.
        it "should give an Oracle one point from the class" do
          as('Oracle')
          grant(1)

          expect(pool).to eq('max' => 1, 'current' => 1)
        end

        it "should count a feat's point once while the feat is held" do
          as('Monk', :feats => { 'charclass' => [ 'Qi Spells' ] })
          grant(1)

          expect(pool['max']).to eq 1
        end

        it "should add to the points already held" do
          as('Oracle')
          hold(1, 1)
          grant(1)

          expect(pool).to eq('max' => 2, 'current' => 2)
        end

        it "should stop at three" do
          as('Oracle')
          hold(3, 3)
          grant(1)

          expect(pool['max']).to eq 3
        end

        it "should read a signed delta the same as a bare number" do
          as('Oracle')
          hold(1, 1)
          grant('+1')

          expect(pool['max']).to eq 2
        end

        it "should leave spent points spent" do
          as('Oracle')
          hold(2, 0)
          grant(1)

          expect(pool).to eq('max' => 3, 'current' => 0)
        end
      end

      describe :focus_pool_sources do
        def total
          Pf2emagic.expected_focus_pool(Character[@char.id])
        end

        it "should count the class's point" do
          as('Oracle')

          expect(total).to eq 1
        end

        # A Druid's order restates the class's point rather than adding a second one.
        it "should count a specialty that restates the class's point once" do
          as('Druid', :specialize => 'Animal')

          expect(total).to eq 1
        end

        it "should count a point from each feat that grants one" do
          as('Monk', :feats => { 'charclass' => [ 'Qi Spells', 'Advanced Qi Spells' ] })

          expect(total).to eq 2
        end

        it "should count a feat whose point comes with the subclass spell it chooses" do
          as('Fighter', :feats => { 'charclass' => [ 'Sorcerer Dedication', 'Basic Bloodline Spell' ] })

          expect(total).to eq 1
        end

        it "should count an archetype specialty's point" do
          as('Wizard', :archetypes => { 'archetype1' => 'Druid Archetype', 'archetype_specialty1' => 'Animal' })

          expect(total).to eq 1
        end

        it "should stop at three" do
          as('Oracle', :feats => { 'charclass' => [ 'Qi Spells', 'Advanced Qi Spells', 'Master Qi Spells' ] })

          expect(total).to eq 3
        end

        it "should find nothing for a class without focus spells" do
          as('Fighter')

          expect(total).to eq 0
        end
      end

      # Every class that starts with focus spells starts with one point.
      describe "a first-level character built through the real commands" do
        %w{Bard Champion Druid Oracle Witch}.each do |charclass|
          it "should give a #{charclass} one focus point" do
            built = Pf2e::AutoBuilder.new(@char).build_level_one(charclass)
            held = Character[built.id].magic.focus_pool

            expect(held).to eq('max' => 1, 'current' => 1)
            expect(Pf2emagic.expected_focus_pool(Character[built.id])).to eq 1
          end
        end
      end
    end
  end
end
