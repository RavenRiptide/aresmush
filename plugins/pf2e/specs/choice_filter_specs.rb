require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What narrows a feat's own choice, held one entry per restricted open slot.
    #
    # A repeatable feat taken twice in one level opens two slots under one name. One taking can be
    # restricted - Assurance from Stylish Tricks, held to Acrobatics or the style skill - while the
    # other is not, so a restriction belongs to a slot rather than to the name. Open slots with no
    # entry are unrestricted, and a pick spends the most restrictive slot it fits.
    describe "a feat choice's narrowing" do

      def char(to_assign)
        double(:pf2_to_assign => to_assign)
      end

      def held(slots, filters)
        { 'feat choice' => { 'Assurance' => slots }, 'feat choice filter' => { 'Assurance' => filters } }
      end

      def offered
        %w(Acrobatics Arcana Diplomacy Society)
      end

      def style
        { 'options' => %w(Acrobatics Diplomacy) }
      end

      describe :narrow_choice_options do
        it "should offer everything while an open slot has no entry" do
          narrowed = Pf2e.narrow_choice_options(char(held(%w(open open), [ style ])), 'Assurance', offered)

          expect(narrowed).to eq offered
        end

        it "should offer what the entries allow when every open slot has one" do
          narrowed = Pf2e.narrow_choice_options(char(held(%w(open), [ style ])), 'Assurance', offered)

          expect(narrowed).to eq %w(Acrobatics Diplomacy)
        end

        it "should offer what any of several entries allows" do
          entries = [ style, { 'options' => %w(Society) } ]
          narrowed = Pf2e.narrow_choice_options(char(held(%w(open open), entries)), 'Assurance', offered)

          expect(narrowed).to eq %w(Acrobatics Diplomacy Society)
        end

        # A draft open when entries became a list holds the one hash it was given.
        it "should read a single stored hash as one entry" do
          narrowed = Pf2e.narrow_choice_options(char(held(%w(open), style)), 'Assurance', offered)

          expect(narrowed).to eq %w(Acrobatics Diplomacy)
        end
      end

      describe :fill_feat_choice do
        it "should spend the most restrictive entry the pick fits" do
          to_assign = held(%w(open open), [ { 'options' => offered }, { 'options' => %w(Acrobatics) } ])

          Pf2e.fill_feat_choice(to_assign, 'Assurance', 'Acrobatics')

          expect(to_assign['feat choice filter']['Assurance']).to eq [ { 'options' => offered } ]
        end

        it "should leave the entries alone when the pick goes to an unrestricted slot" do
          to_assign = held(%w(open open), [ style ])

          Pf2e.fill_feat_choice(to_assign, 'Assurance', 'Arcana')

          expect(to_assign['feat choice']['Assurance']).to eq %w(Arcana open)
          expect(to_assign['feat choice filter']['Assurance']).to eq [ style ]
        end

        it "should clear the entries once no slot is open" do
          to_assign = held(%w(open), [ style ])

          Pf2e.fill_feat_choice(to_assign, 'Assurance', 'Diplomacy')

          expect(to_assign['feat choice filter']).to eq({})
        end
      end

      describe :store_choice_filter do
        it "should add an entry for each restricted slot" do
          to_assign = held(%w(open open), [ style ])

          Pf2e.store_choice_filter(to_assign, 'Assurance', { 'options' => %w(Society) })

          expect(to_assign['feat choice filter']['Assurance']).to eq [ style, { 'options' => %w(Society) } ]
        end
      end
    end
  end
end
