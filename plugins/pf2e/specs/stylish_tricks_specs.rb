require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Stylish Tricks, the Swashbuckler's 3rd, 7th and 15th level feature (Player Core 2): "You also
    # gain an additional skill feat at these levels. This feat must be for Acrobatics or the trained
    # skill from your swashbuckler's style."
    #
    # A Wit's style skill is Diplomacy. Level 3 also has a general feat slot, and Assurance is a
    # general feat as well as a skill feat, so one level can open two Assurance picks: one held to
    # the two skills, one free.
    describe "Stylish Tricks", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Stylish#{rand(1000000)}")
        @char.update(:pf2_base_info => { 'charclass' => 'Swashbuckler', 'specialize' => 'Wit', 'ancestry' => 'Human' },
                     :pf2_feats => {},
                     :pf2_level => 2, :advancing => true,
                     :pf2_to_assign => { 'feat choice' => { 'Stylish Tricks' => [ 'open' ] } },
                     :pf2_advancement => {})

        %w(Acrobatics Arcana Diplomacy Society).each do |skill|
          Pf2eSkills.create_skill_for_char(skill, @char)
          Pf2eSkills.update_skill_for_char(skill, @char, 'trained')
        end
      end

      after(:each) do
        @char.skills.each(&:delete) if @char
        Pf2e::Audit.delete_all!(@char) if @char
        @char.delete if @char
      end

      def char
        Character[@char.id]
      end

      def options(choice)
        _key, block = Pf2e.validate_feat_choice(char, choice)

        Pf2e.choice_options(char, choice, block)
      end

      # As advance/option does: refused unless the value is on offer, staged if it is.
      def option(choice, value)
        key, block = Pf2e.validate_feat_choice(char, choice)
        matched = Pf2e.match_choice_option(char, key, block, value)

        return false unless matched

        Pf2e.stage_feat_choice(char, key, block, matched, nil)
        true
      end

      # As advance/feat general=Assurance does.
      def take_general(feat)
        found = Pf2e.get_feat_details(feat)
        to_assign = char.pf2_to_assign
        advancement = char.pf2_advancement

        gained = Advancement::FeatGain.apply(char, found[0], found[1],
          :bucket => 'general', :to_assign => to_assign, :advancement => advancement)

        @char.update(:pf2_to_assign => to_assign, :pf2_advancement => advancement)
        gained[:after_save].each(&:call)
      end

      describe "the feat" do
        it "should offer only feats for Acrobatics or the style skill" do
          offered = options('Stylish Tricks')

          expect(offered).to include('Cat Fall', 'Bon Mot')
          expect(offered).to_not include('Arcane Sense', 'Courtly Graces')

          offered.each do |name|
            next if name == 'Assurance'

            skills = Array(Pf2e.get_feat_details(name)[1]['assoc_skill'])

            expect(skills & %w(Acrobatics Diplomacy)).to_not be_empty, name
          end
        end

        it "should offer Assurance, whose skill is picked when it is taken" do
          expect(options('Stylish Tricks')).to include('Assurance')
        end

        it "should offer Rolling Landing once Cat Fall is held" do
          @char.update(:pf2_feats => { 'skill' => [ 'Cat Fall' ] })

          expect(options('Stylish Tricks')).to include('Rolling Landing')
        end
      end

      describe "an Assurance taken through it" do
        it "should offer only Acrobatics or the style skill" do
          option('Stylish Tricks', 'Assurance')

          expect(options('Assurance')).to eq %w(Acrobatics Diplomacy)
          expect(option('Assurance', 'Arcana')).to be false
          expect(option('Assurance', 'Acrobatics')).to be true
        end

        it "should leave an Assurance taken in a feat slot free" do
          take_general('Assurance')

          expect(options('Assurance')).to include('Arcana', 'Society')
        end
      end

      # Two Assurance picks open at once. Whichever was taken first, a skill outside the two goes to
      # the free one, and the restricted one is still held to the two.
      describe "two Assurance picks at once" do
        def both(order)
          order.each { |source| source == :stylish ? option('Stylish Tricks', 'Assurance') : take_general('Assurance') }
        end

        [ [ :stylish, :general ], [ :general, :stylish ] ].each do |order|
          context "taken #{order.join(' then ')}" do
            it "should offer every trained skill while both are open" do
              both(order)

              expect(options('Assurance')).to eq %w(Acrobatics Arcana Diplomacy Society)
            end

            it "should put a skill outside the two in the free pick" do
              both(order)

              expect(option('Assurance', 'Arcana')).to be true
              expect(options('Assurance')).to eq %w(Acrobatics Diplomacy)
              expect(option('Assurance', 'Society')).to be false
            end

            it "should put Acrobatics in the restricted pick, leaving the free one free" do
              both(order)

              expect(option('Assurance', 'Acrobatics')).to be true
              expect(options('Assurance')).to eq %w(Arcana Diplomacy Society)
            end
          end
        end
      end
    end
  end
end
