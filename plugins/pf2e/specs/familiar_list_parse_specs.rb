require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A list of familiar abilities as a player types it: commas between abilities, a choice in parentheses.
    describe "a typed list of familiar abilities" do

      def parse(text)
        Familiar::Choices.parse_list(text)
      end

      it "should read abilities and their choices" do
        expect(parse('Fast Movement (land), Tough')).to eq [ { 'name' => 'Fast Movement', 'choice' => 'land' },
                                                             { 'name' => 'Tough' } ]
      end

      it "should keep a comma inside parentheses with its choice" do
        expect(parse('Resistance (fire, cold), Darkvision')).to eq [ { 'name' => 'Resistance', 'choice' => 'fire, cold' },
                                                                     { 'name' => 'Darkvision' } ]
      end

      it "should collapse spacing" do
        expect(parse("  Darkvision ,\tSkilled  ( Arcana ) ")).to eq [ { 'name' => 'Darkvision' },
                                                                     { 'name' => 'Skilled', 'choice' => 'Arcana' } ]
      end

      it "should treat empty parentheses as no choice" do
        expect(parse('Tough ()')).to eq [ { 'name' => 'Tough' } ]
      end

      it "should refuse parentheses that don't pair" do
        expect(parse('Skilled (Arcana')).to be_nil
        expect(parse('Skilled Arcana)')).to be_nil
      end

      it "should refuse parentheses inside parentheses" do
        expect(parse('Skilled ((Arcana))')).to be_nil
      end

      it "should refuse text after a choice" do
        expect(parse('Skilled (Arcana) extra')).to be_nil
      end

      it "should refuse an empty entry" do
        expect(parse('Tough,, Darkvision')).to be_nil
        expect(parse('Tough,')).to be_nil
      end

      it "should refuse nothing at all, and a list too long to be one" do
        expect(parse('   ')).to be_nil
        expect(parse('Tough, ' * 40)).to be_nil
      end
    end
  end
end
