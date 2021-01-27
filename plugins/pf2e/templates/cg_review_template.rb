module AresMUSH
  module Pf2e

    class PF2CGReviewDisplay < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :sheet

      def initialize(char, sheet)
        @char = char
        @sheet = sheet

        super File.dirname(__FILE__) + "/cg_review.erb"
      end

      def elements
        base_info = @sheet.pf2_base_info
        @ancestry = base_info[:ancestry]
        @heritage = base_info[:heritage]
        @background = base_info[:background]
        @charclass = base_info[:charclass]
        @subclass = base_info[:specialize]

        @ancestry_info = @ancestry.blank? ? Global.read_config('pf2e_ancestry', @ancestry) : nil
        @heritage_info = @heritage.blank? ? Global.read_config('pf2e_heritage', @heritage) : nil
        @background_info = @background.blank? ? Global.read_config('pf2e_background', @background) : nil
        @charclass_info = @charclass.blank? ? Global.read_config('pf2e_class', @charclass) : nil
      end

      def name
        @char.name
      end

      def ancestry
        @ancestry.blank? ? @ancestry : nil
      end

      def heritage
        @heritage.blank? ? @heritage : nil
      end

      def background
        @background.blank? ? @background : nil
      end

      def charclass
        @charclass.blank? ? @charclass : nil
      end

      def subclass
        @subclass.blank? ? @subclass : nil
      end

      def hp
        @ancestry_info["HP"] + self.charclass_info["HP"]
      end

      def size
        @ancestry_info["Size"]
      end

      def speed
        @ancestry_info["Speed"]
      end

      def traits
        @ancestry_info["traits"] + @heritage_info["traits"] + [ @charclass ].uniq.sort.join(", ")
      end

      def ancestry_boosts
        @ancestry_info["abl_boosts"]
      end

      def free_ancestry_boosts
        @ancestry_info["abl_boosts_open"]
      end

      def background_boosts
        list = @background_info["req_abl_boosts"]
        list.empty? "None required." : list.join(" or ")
      end

      def free_bg_boosts
        @background_info["abl_boosts_open"]
      end

      def charclass_boosts
        list = @charclass_info["key_score"]
        list.join("or")
      end

      def specials
        specials = @ancestry_info["special"] + @heritage_info["special"] + @background_info["special"].flatten!
        if Pf2e.character_has?(specials, "Low-Light Vision") && @heritage == "Dar"
          specials = specials.delete_at specials.index("Low-Light Vision") + [ "Darkvision" ]
        end
        specials.empty? ? "No special abilities or senses." : specials.sort.join(", ")
      end

    end
  end
end
