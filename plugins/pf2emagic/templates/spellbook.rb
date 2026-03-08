module AresMUSH
  module Pf2emagic

    class PF2SpellbookTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :spellbook, :client

      def initialize(char, charclass, spellbook, client, title_key='pf2emagic.spellbook_title')
        @char = char
        @charclass = charclass
        @spellbook = spellbook
        @client = client
        @title_key = title_key

        super File.dirname(__FILE__) + "/spellbook.erb"
      end

      def title
        t(@title_key, :name => @char.name)
      end

      def spellbook_list
        list = []

        @spellbook.each_pair do |key, value|
          # If they asked for just one level, value can be an array. Otherwise, it's a hash.
          if value.is_a? Array
            header = "#{title_color}#{@charclass}:%xn%r"
            data = "#{item_color}#{key}:%xn #{value.sort.join(", ")}"

            list << "#{header}#{data}"
          else
            sublist = []

            # Value being a hash, sometimes it can be out of order. Normalize that prior to processing.
            value = Pf2emagic.sort_level_spell_list(value)

            value.each_pair do |level, spell_list|
              header = "#{item_color}#{spellbook_level_label(level)}:%xn"
              data = "#{spell_list.sort.join(", ")}"

              sublist << "#{header} #{data}"
            end

            list << "#{title_color}#{key}:%xn%r#{sublist.join("%r")}"
          end

        end

        list
      end

      def spellbook_level_label(level)
        level_str = level.to_s
        return 'Cantrips' if level_str.downcase == 'cantrip'

        level_num = level_str.to_i
        "#{ordinal(level_num)}-level"
      end

      def ordinal(number)
        abs_num = number.to_i.abs

        suffix = case abs_num % 10
                 when 1 then 'st'
                 when 2 then 'nd'
                 when 3 then 'rd'
                 else 'th'
                 end

        "#{number}#{suffix}"
      end

    end
  end
end
