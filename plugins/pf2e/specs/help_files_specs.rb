require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The game reads every help file's header when it starts, and stops at one it cannot read.
    describe "the PF2e help files" do
      files = Dir[File.join(__dir__, '..', 'help', 'en', '*.md')]

      it "should each have a header the game can read, with a summary" do
        unread = files.reject do |path|
          MarkdownFile.new(path).metadata['summary'].is_a?(String)
        rescue RuntimeError
          false
        end

        expect(unread.map { |path| File.basename(path) }).to eq []
      end

      it "should give no topic to two files" do
        names = files.flat_map { |path| ([ File.basename(path, '.md') ] + Array((MarkdownFile.new(path).metadata rescue {})['aliases'])).uniq }

        expect(names.tally.select { |_name, count| count > 1 }.keys).to eq []
      end
    end
  end
end
