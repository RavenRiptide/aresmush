module AresMUSH
  module Pf2e

    # Cold iron and silver armor against creatures weak to them (GM Core): a creature with weakness to the
    # armor's material that critically fails an unarmed attack against its wearer is sickened 1. A material
    # does this when its row in `pf2e_materials.yml` says `sickens_weak`.
    #
    # The rule's other half, a creature weak to the material being sickened while it wears the armor, is left
    # to the GM: it almost never happens.
    module MaterialArmor

      def self.after_strike(scene, attack, degree, out)
        return unless degree == Degree::CRITICAL_FAILURE && unarmed?(attack)

        material = sickening(scene.target.holder)

        return unless material && weak?(scene.actor.holder, material)

        out['lines'] << Telling.event('pf2e.material_armor_sickens', :actor => scene.actor.label,
                                      :target => scene.target.label, :material => material.downcase)
        Acting.condition_consequence(scene, scene.actor, { 'condition' => 'Sickened', 'value' => 1 }, out)
      end

      # A character's unarmed attack says so; a creature's natural attack carries the unarmed trait.
      def self.unarmed?(attack)
        attack['unarmed'] || Pf2e.has_trait?(attack['traits'], 'unarmed')
      end

      # The material of the armor they wear, where it sickens what is weak to it, or nil.
      def self.sickening(holder)
        return nil unless Actors.of(holder).carries_items?

        armor = Pf2egear::Inventory.held(holder, 'armor').find(&:equipped)
        found = armor && Pf2egear::Materials.of(armor)

        found && found.last['sickens_weak'] ? found.first : nil
      end

      def self.weak?(holder, material)
        wanted = Domains.slug(material)

        Array(IWR.for(holder)['weakness']).any? do |one|
          Array(one['type']).any? { |type| Domains.slug(type) == wanted }
        end
      end
    end
  end
end
