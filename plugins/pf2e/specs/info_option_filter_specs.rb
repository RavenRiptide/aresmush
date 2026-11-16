require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Narrowing a long option list.
    #
    # The message behind a big pool says "236 eligible options, too many to list here" and names
    # the info command - but that command then hands back six pages, which is barely more use than
    # the refusal was. A filter is what makes the hint actionable.
    describe :info_option_display do

      def lores
        [ 'Architecture Lore', 'Arboreal Lore', 'Baking Lore', 'Dragon Lore', 'Engineering Lore' ]
      end

      # The command as dispatched; the display reads its page, and its words for the next-page hint.
      def cmd(page = 1)
        double(:prefix => nil, :root => 'cg', :switch => 'info', :args => 'Additional Lore', :page => page)
      end

      it "should list a short pool inline" do
        display = Pf2e.info_option_display('Additional Lore', lores, cmd)

        expect(display[:text]).to include 'Dragon Lore'
      end

      it "should keep only the options containing the filter" do
        display = Pf2e.info_option_display('Additional Lore', lores, cmd, 'arch')

        expect(display[:text]).to include 'Architecture Lore'
        expect(display[:text]).to_not include 'Baking Lore'
      end

      it "should ignore the case of the filter" do
        display = Pf2e.info_option_display('Additional Lore', lores, cmd, 'DRAGON')

        expect(display[:text]).to include 'Dragon Lore'
      end

      it "should match anywhere in the name, not only the start" do
        display = Pf2e.info_option_display('Additional Lore', lores, cmd, 'bore')

        expect(display[:text]).to include 'Arboreal Lore'
      end

      # Saying "nothing matched dragn" is actionable; an empty list is not, and the old
      # no-options message would have blamed the pool rather than the filter.
      it "should say the filter matched nothing, and name the filter" do
        display = Pf2e.info_option_display('Additional Lore', lores, cmd, 'zzz')

        expect(display[:error]).to include 'zzz'
      end

      it "should still say the pool is empty when there was nothing to filter" do
        display = Pf2e.info_option_display('Additional Lore', [], cmd, 'arch')

        expect(display[:error]).to include 'Additional Lore'
      end

      it "should count pages against the filtered list, not the whole pool" do
        many = (1..60).map { |n| "Filler #{n} Lore" } + [ 'Dragon Lore' ]
        display = Pf2e.info_option_display('Additional Lore', many, cmd, 'dragon')

        expect(display[:text]).to include 'Dragon Lore'
        expect(display[:error]).to be_nil
      end

      # A pool too long for one page says how to reach the next one, in the words of the command
      # that asked for it.
      it "should name the command for the next page under a long list" do
        many = (1..60).map { |n| "Filler #{n} Lore" }
        display = Pf2e.info_option_display('Additional Lore', many, cmd)

        expect(display[:text]).to include 'cg/info2 Additional Lore'
      end

      # A formula choice lists like the `formulas` screen: a section per catalogue, a heading per
      # item level, and whole names, never cut to a column.
      describe "a formula choice" do
        let(:long_name) { 'Elixir of Gender Transformation (Lesser)' }

        before(:each) do
          levels = { 'Arsenic' => 1, long_name => 1, 'Belladonna' => 2, 'Wayfinder' => 2 }

          allow(Global).to receive(:read_config).and_call_original
          allow(Global).to receive(:read_config).with('pf2e_consumables', anything) { |_, name| { 'level' => levels[name] } }
          allow(Global).to receive(:read_config).with('pf2e_magicitem', anything) { |_, name| { 'level' => levels[name] } }
          allow(Crafting).to receive(:pool_category) do |_filter, name|
            name == 'Wayfinder' ? [ 'magicitem', name ] : [ 'consumables', name ]
          end
        end

        def formula_cmd(page = 1)
          double(:prefix => nil, :root => 'cg', :switch => 'info', :args => 'Formula Book', :page => page)
        end

        def show(options, filter = nil, page = 1, formulas = { 'category' => %w(magicitem consumables) })
          Pf2e.info_option_display('Formula Book', options, formula_cmd(page), filter, :formulas => formulas)
        end

        it "should show each formula's whole name under its level" do
          text = show([ 'Arsenic', long_name, 'Belladonna' ])[:text]

          expect(text).to include long_name
          expect(text).to include 'Level 1'
          expect(text).to include 'Level 2'
          expect(text.index('Level 1')).to be < text.index('Belladonna')
        end

        it "should put the catalogues in the filter's order, under their labels" do
          text = show([ 'Arsenic', 'Wayfinder' ])[:text]

          expect(text).to include 'Magic Items'
          expect(text.index('Magic Items')).to be < text.index('Consumables')
        end

        it "should title the list with the choice" do
          expect(show([ 'Arsenic' ])[:text]).to include 'Formula Book'
        end

        it "should still narrow by the filter" do
          text = show([ 'Arsenic', 'Belladonna' ], 'bella')[:text]

          expect(text).to include 'Belladonna'
          expect(text).to_not include 'Arsenic'
        end

        it "should page a long list and name the command for the next page" do
          many = (1..30).map { |n| "Filler #{n}" } + (1..30).map { |n| "Later #{n}" }
          allow(Global).to receive(:read_config).with('pf2e_consumables', anything) do |_, name|
            { 'level' => name.start_with?('Filler') ? 1 : 2 }
          end

          first = show(many)[:text]
          second = show(many, nil, 2)[:text]

          expect(first).to include 'Filler 1,'
          expect(first).to_not include 'Later 1,'
          expect(first).to include 'cg/info2 Formula Book'
          expect(second).to include 'Later 1,'
        end

        it "should refuse a page past the end" do
          expect(show([ 'Arsenic' ], nil, 5)[:error]).to_not be_nil
        end
      end
    end
  end
end
