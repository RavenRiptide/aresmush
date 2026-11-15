module AresMUSH
  module Pf2egear

    # A shield boss or shield spikes attached to one shield (`gear/attach`, `gear/detach`). A shield holds one
    # at a time, and one is on one shield at a time. A Strike with it counts as a weapon of the shield's
    # precious material, if it has one (`Materials.slugs`).
    module ShieldAttach

      # Weapons in this group are what attaches to a shield.
      GROUP = 'shield'.freeze

      def self.attach(char, shield_number, weapon_number)
        shield = Inventory.item(char, 'shields', shield_number)

        return shield if shield.err?

        weapon = Inventory.item(char, 'weapons', weapon_number)

        return weapon if weapon.err?

        shield, weapon = shield.state, weapon.state

        return Pf2e::Err.new(:not_attachable, 'pf2egear.attach_not_attachable', 'weapon' => weapon.name) unless
          weapon.group.to_s.casecmp?(GROUP)
        return Pf2e::Err.new(:has_one, 'pf2egear.attach_has_one', 'shield' => shield.name, 'weapon' => shield.weapon.name) if
          shield.weapon
        on = Materials.shield_of(weapon)
        return Pf2e::Err.new(:elsewhere, 'pf2egear.attach_elsewhere', 'weapon' => weapon.name, 'shield' => on.name) if on

        shield.update(:weapon => weapon)

        Pf2e::Ok.new(:state => { 'shield' => shield.name, 'weapon' => weapon.name })
      end

      def self.detach(char, shield_number)
        shield = Inventory.item(char, 'shields', shield_number)

        return shield if shield.err?

        shield = shield.state
        weapon = shield.weapon

        return Pf2e::Err.new(:nothing, 'pf2egear.detach_nothing', 'shield' => shield.name) unless weapon

        shield.update(:weapon => nil)

        Pf2e::Ok.new(:state => { 'shield' => shield.name, 'weapon' => weapon.name })
      end
    end
  end
end
