module AresMUSH
  module Pf2e

    # Ammunition of a precious material, shot from a weapon that shoots.
    #
    # Ordinary arrows, bolts and bullets are not counted: a bow always has them, and nothing sells them.
    # Ammunition of cold iron or silver is an item the archer carries. Saying the material on a Strike -
    # `/cold iron` - shoots one piece of it, which is used up whether or not it hits. A weapon that shoots
    # nothing - a sword, a fist, a thrown dagger - is made of what its wielder says it is.
    module Ammunition

      # A weapon that shoots: ranged, and neither thrown itself nor a bomb.
      def self.shot?(attack)
        thrown = Array(attack['traits']).any? { |trait| trait.to_s.downcase.start_with?('thrown') }

        attack['ranged'] && !attack['bomb'] && !attack['unarmed'] && !thrown ? true : false
      end

      # The precious materials said of a Strike, as damage knows them.
      def self.said(words)
        Array(words).map { |word| Domains.slug(word) } & IWR::MATERIALS
      end

      # The material a catalogue item is ammunition of, where it is.
      def self.material(name)
        made_of = Consumables.info(name).dig('ammunition', 'material')

        made_of ? Domains.slug(made_of) : nil
      end

      # The piece they would shoot of a material: of two alike, the one that will not last.
      def self.carried(holder, material)
        Equipment.soonest_first(Pf2egear::Inventory.held(holder, 'consumables')).find { |item| material(item.name) == material }
      end

      # What a Strike shoots beyond the ordinary: a piece of each material said, for someone who carries
      # their own things, shooting a weapon that shoots. Refused where they carry none of one.
      def self.for_strike(holder, attack, words)
        return Ok.new(:state => []) unless shot?(attack) && Actors.of(holder).carries_items?

        pieces = said(words).map do |material|
          carried(holder, material) || (return Err.new(:no_ammunition, 'pf2e.ammunition_none', 'weapon' => attack['name'],
                                                                                             'material' => material.tr('-', ' ')))
        end

        Ok.new(:state => pieces)
      end

      # The shot is made, and what it shot is gone.
      def self.shoot!(holder, pieces, out)
        pieces.each do |piece|
          name = piece.name
          left = piece.quantity.to_i - 1

          Consumables.spend!(holder, piece.id)
          out['lines'] << Telling.event('pf2e.ammunition_shot', 'item' => name, 'left' => left)
        end
      end
    end
  end
end
