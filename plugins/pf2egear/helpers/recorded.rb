module AresMUSH
  module Pf2egear

    # Using an item or paying someone in an encounter goes on the encounter's history, so the GM can take
    # it back (`Pf2e::History`). Outside one, nothing is recorded.
    class PF2PayCmd
      def recorded_people
        [ Pf2e.get_character(self.target, enactor) ].compact
      end
    end

    [ PF2UseItemCmd, PF2PayCmd ].each { |command| command.prepend(Pf2e::Recorded) }
  end
end
