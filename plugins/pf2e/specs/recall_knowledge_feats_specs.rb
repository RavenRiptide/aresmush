require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Feats that ask for a skill with the Recall Knowledge action. pf2e_skills marks those skills
    # `recall_knowledge: true`: the knowledge skills and every lore. Automatic Knowledge picks one the
    # character is an expert in and has Assurance in; Dubious Knowledge asks only to be trained in one.
    describe "Recall Knowledge feats" do

      describe "for a character", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Knower#{rand(1000000)}", :pf2_level => 2,
            :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human', 'heritage' => 'Changeling' })
        end

        after(:each) do
          @char.skills.each(&:delete) if @char
          Pf2e::Audit.delete_all!(@char) if @char
          @char.delete if @char
        end

        def char
          Character[@char.id]
        end

        def skilled(ranks)
          ranks.each_pair do |skill, rank|
            Pf2eSkills.create_skill_for_char(skill, @char)
            Pf2eSkills.update_skill_for_char(skill, @char, rank)
          end
        end

        # Feats held, and the skill each choice was made for, as the level tracker records them.
        def holding(feats, choices = {})
          @char.update(:pf2_feats => { 'skill' => feats },
                       :pf2_level_tracker => { '1' => { 'feat_choices' => choices } })
        end

        def details(feat)
          Pf2e.get_feat_details(feat)[1]
        end

        describe "the skill choice filters" do
          it "should keep only skills with the Recall Knowledge action" do
            skilled('Arcana' => 'expert', 'Athletics' => 'expert', 'Warfare Lore' => 'expert')

            expect(Pf2e.choice_skill_pool(char, 'min_prof' => 'expert', 'recall_knowledge' => true))
              .to eq [ 'Arcana', 'Warfare Lore' ]
          end

          it "should keep only skills chosen for the feat it names" do
            skilled('Arcana' => 'trained', 'Society' => 'trained')
            holding([ 'Assurance' ], 'Assurance' => [ 'Society' ])

            expect(Pf2e.choice_skill_pool(char, 'with_feat' => 'Assurance')).to eq [ 'Society' ]
          end
        end

        describe "Automatic Knowledge" do
          def options
            Pf2e.choice_options(char, 'Automatic Knowledge', Pf2e.feat_choice_def(details('Automatic Knowledge')))
          end

          it "should offer an expert Recall Knowledge skill the character has Assurance in" do
            skilled('Arcana' => 'expert', 'Society' => 'trained', 'Athletics' => 'expert')
            holding([ 'Assurance', 'Assurance', 'Assurance' ], 'Assurance' => [ 'Arcana', 'Society', 'Athletics' ])

            expect(options).to eq [ 'Arcana' ]
            expect(Pf2e.can_take_feat_details?(char, 'Automatic Knowledge', details('Automatic Knowledge'))).to eq true
          end

          it "should not offer a skill it was already taken for" do
            skilled('Arcana' => 'expert')
            holding([ 'Assurance', 'Automatic Knowledge' ], 'Assurance' => [ 'Arcana' ], 'Automatic Knowledge' => [ 'Arcana' ])

            expect(options).to eq []
          end

          it "should be refused, saying why, with no skill left to pick" do
            skilled('Athletics' => 'expert')
            holding([ 'Assurance' ], 'Assurance' => [ 'Athletics' ])

            expect(Pf2e.can_take_feat_details?(char, 'Automatic Knowledge', details('Automatic Knowledge'))).to eq false
            expect(Pf2e.explain_feat_block(char, details('Automatic Knowledge'), 'Automatic Knowledge'))
              .to include("there's nothing left to choose for it")
          end

          # Without Assurance the prerequisite is what fails, so that is what the player hears.
          it "should leave a missing prerequisite to the usual message" do
            skilled('Arcana' => 'expert')

            expect(Pf2e.can_take_feat_details?(char, 'Automatic Knowledge', details('Automatic Knowledge'))).to eq false
            expect(Pf2e.explain_feat_block(char, details('Automatic Knowledge'), 'Automatic Knowledge')).to be_nil
          end
        end

        describe "the empty choice" do
          it "should refuse Assurance once every trained skill has it" do
            skilled('Arcana' => 'trained')
            holding([ 'Assurance' ], 'Assurance' => [ 'Arcana' ])

            expect(Pf2e.can_take_feat_details?(char, 'Assurance', details('Assurance'))).to eq false
          end

          # A grant settles or narrows its own pick.
          it "should let a grant skip it" do
            skilled('Arcana' => 'trained')
            holding([ 'Assurance' ], 'Assurance' => [ 'Arcana' ])

            expect(Pf2e.can_take_feat_details?(char, 'Assurance', details('Assurance'), :choice_gate => false)).to eq true
          end
        end

        describe "Dubious Knowledge" do
          def meets?
            Pf2e.meets_prereqs?(char, details('Dubious Knowledge')['prereq'], 2)
          end

          it "should fail with no Recall Knowledge skill trained" do
            skilled('Athletics' => 'trained')

            expect(meets?).to eq false
          end

          it "should pass on a trained knowledge skill" do
            skilled('Athletics' => 'trained', 'Society' => 'trained')

            expect(meets?).to eq true
          end

          it "should pass on a trained lore" do
            skilled('Warfare Lore' => 'trained')

            expect(meets?).to eq true
          end
        end
      end

      describe "the shipped data" do
        before(:all) do
          @feats = YAML.load_file("game/config/pf2e_feat_skill.yml")['pf2e_feats']
          @skills = YAML.load_file("game/config/pf2e_skills.yml")['pf2e_skills']
        end

        it "should have Automatic Knowledge pick its skill" do
          feat = @feats['Automatic Knowledge']

          expect(feat['assoc_skill']).to be_nil
          expect(feat['prereq']).to eq('level' => 2, 'feat' => [ 'Assurance' ])
          expect(feat['feat_choice']['from_skills'])
            .to eq('min_prof' => 'expert', 'recall_knowledge' => true, 'with_feat' => 'Assurance')
        end

        it "should have Dubious Knowledge ask for a trained Recall Knowledge skill" do
          feat = @feats['Dubious Knowledge']

          expect(feat['prereq']).to eq('level' => 1, 'recall_skill' => 'trained')
          expect(feat['assoc_skill']).to eq %w(Arcana Crafting Medicine Nature Occultism Religion Society)
        end

        it "should mark exactly the knowledge skills and the lores as Recall Knowledge skills" do
          marked = @skills.select { |_name, info| info['recall_knowledge'] }.keys

          expect(marked).to include('Arcana', 'Crafting', 'Medicine', 'Nature', 'Occultism', 'Religion', 'Society')
          expect(marked).to_not include('Acrobatics', 'Athletics', 'Deception', 'Diplomacy', 'Intimidation',
                                        'Performance', 'Stealth', 'Survival', 'Thievery')
          expect(@skills.keys.select { |name| name.end_with?(' Lore') } - marked).to eq []
        end

        it "should show a recall_skill prereq in words" do
          expect(Pf2e.format_feat('Dubious Knowledge', @feats['Dubious Knowledge']))
            .to include('Skill requirement:%xn trained in a skill with the Recall Knowledge action')
        end
      end
    end
  end
end
