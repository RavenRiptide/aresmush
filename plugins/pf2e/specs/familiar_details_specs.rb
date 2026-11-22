require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a player may type for their familiar. Name and species are free text a player types and staff
    # read in `app`, a request and every sheet, so nothing that could break a display or a parser may get in.
    describe Familiar::Details do

      RESTRICTED = [ 'me', 'here', 'Althea', 'Kor', 'Navos' ].freeze

      def name(text, taken: [])
        Familiar::Details.name(text, :restricted => RESTRICTED, :taken => ->(named) { taken.any? { |t| t.casecmp?(named) } })
      end

      def species(text)
        Familiar::Details.species(text, :restricted => RESTRICTED)
      end

      # One word, as a character's name is.
      describe "a name" do
        it "should take an ordinary name, trimmed" do
          expect(name('  Smudge ').state).to eq 'Smudge'
        end

        it "should take apostrophes and hyphens" do
          expect(name("Cor'lana").ok?).to be true
          expect(name('Mist-Wing').ok?).to be true
        end

        {
          'nothing' => '',
          'only spaces' => '   ',
          'a second word' => "Cor'lana Lupecyll",
          'a newline between words' => "Smudge\nInky",
          'an accent, which a character name refuses' => 'Émile',
          'an accent typed as a combining mark' => "Émile",
          'a period' => 'Smudge.',
          'a digit' => 'R2',
          'one letter' => 'S',
          'a line break code' => 'Smudge%r%r',
          'a colour code' => '%xrRed',
          'a backslash' => 'Smudge\\n',
          'an escape sequence' => "\e[31mRed",
          'a slash, which splits e/sheet' => 'Smudge/combat',
          'an equals sign, which splits familiar/reject' => 'Bob=1',
          'a comma, which splits prepare/familiar' => 'Smudge, Inky',
          'parentheses, which hold a choice' => 'Smudge (Arcana)',
          'an encounter reference' => '#7',
          'a leading number, which reads as a count' => '7 Smudge',
          'a leading apostrophe' => "'Smudge",
          'a right-to-left override' => "Smudge\u202Egdums",
          'a zero-width space' => "Smu​dge",
          'an emoji' => "Smudge \u{1F408}",
          'a semicolon' => 'Smudge;Inky',
          'too many characters' => 'a' * 31
        }.each_pair do |what, text|
          it "should refuse #{what}" do
            expect(name(text).err?).to be true
          end
        end

        it "should say why a second word is refused" do
          expect(name('Smudge Inky').code).to eq :familiar_name_chars
        end

        it "should say how long a name may be" do
          result = name('a' * 31)

          expect(result.code).to eq :familiar_text_long
          expect(result.args['max']).to eq 30
          expect(name('S').code).to eq :familiar_name_short
        end

        it "should refuse a restricted name in any case" do
          expect(name('althea').code).to eq :familiar_name_restricted
          expect(name('HERE').code).to eq :familiar_name_restricted
        end

        it "should refuse a restricted name inside a name" do
          expect(name("Althea's").code).to eq :familiar_word_restricted
          expect(name('Kor-Wing').code).to eq :familiar_word_restricted
        end

        it "should leave the targeting words alone inside a longer name" do
          expect(name('Here-Kitty').ok?).to be true
        end

        it "should not match a restricted name inside a longer word" do
          expect(name('Korvin').ok?).to be true
        end

        it "should refuse a character's name, whatever its case" do
          expect(name('morwen', taken: [ 'Morwen' ]).code).to eq :familiar_name_taken
        end
      end

      describe "a species" do
        it "should take a plain species, trimmed and with single spaces" do
          expect(species('  black   cat ').state).to eq 'black cat'
        end

        it "should take accents, typed either way, and store them composed" do
          expect(species("chouette effraie à crête").ok?).to be true
          expect(species("Émeu").state).to eq "Émeu"
        end

        it "should turn a newline or a tab into a space" do
          expect(species("black\ncat\tof night").state).to eq 'black cat of night'
        end

        it "should refuse a restricted name as a word" do
          expect(species('fragment of Navos').code).to eq :familiar_word_restricted
        end

        it "should allow up to 40 characters" do
          expect(species('a' * 40).ok?).to be true
          expect(species('a' * 41).err?).to be true
        end

        it "should refuse MUSH codes" do
          expect(species('cat%t').err?).to be true
        end
      end

      describe "a form" do
        it "should take a listed form in any case, and store the config's spelling" do
          expect(Familiar::Details.form('Aquatic', :forms => [ 'land', 'aquatic' ]).state).to eq 'aquatic'
        end

        it "should refuse anything else, listing the forms" do
          result = Familiar::Details.form('flying', :forms => [ 'land', 'aquatic' ])

          expect(result.code).to eq :familiar_form_unknown
          expect(result.args['forms']).to eq 'land, aquatic'
        end
      end
    end
  end
end
