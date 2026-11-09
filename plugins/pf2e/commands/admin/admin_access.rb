module AresMUSH
  module Pf2e

    # What `admin/access` and `admin/unaccess` share: the character named, and the kind of access asked
    # for. Spells are the only kind: an uncommon or rare item is reached through its formula instead.
    module NamesAccess
      KINDS = %w{spell}.freeze

      def parse_access_args
        if cmd.args.to_s.include?('=')
          args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

          self.character = trim_arg(args.arg1)
          self.kind = downcase_arg(args.arg2)
          self.name = trim_arg(args.arg3)
        else
          self.character = trim_arg(cmd.args)
        end
      end

      def check_can_change_sheet
        return nil if enactor.has_permission?('manage_sheet')
        return t('dispatcher.not_allowed')
      end

      def check_kind
        return nil if self.kind.nil? || KINDS.include?(self.kind)
        return t('pf2e.access_kinds')
      end

      def subject
        @subject ||= Pf2e.get_character(self.character, enactor)
      end

      # The spell a name means, as [ name, details ], or the message saying why there isn't one.
      def spell
        @spell ||= Pf2emagic.get_spell_details(self.name)
      end
    end

    # admin/access <character>                   lists the spells unlocked for them
    # admin/access <character>/spell=<spell>     unlocks an uncommon or rare spell for them to learn
    class PF2AdminAccessCmd
      include CommandHandler
      include NamesAccess

      attr_accessor :character, :kind, :name

      def parse_args
        parse_access_args
      end

      def required_args
        [ self.character ]
      end

      def handle
        return client.emit_failure(t('pf2e.not_found')) unless subject

        self.name ? unlock : list
      end

      def unlock
        return client.emit_failure(spell) if spell.is_a?(String)

        named, details = spell

        return client.emit_failure(t('pf2e.access_common', :spell => named)) if SpellUnlocks.common?(details)
        # Chargen records its sheet only for a character with no grants, so an unlock waits for approval.
        return client.emit_failure(t('pf2e.access_not_approved', :char => subject.name)) unless subject.is_approved?
        return client.emit_failure(t('pf2e.access_already', :char => subject.name, :spell => named)) if
          SpellUnlocks.unlocked?(subject, named)

        SpellUnlocks.unlock!(subject, named, :by => enactor.name)

        client.emit_success t('pf2e.access_given', :char => subject.name, :spell => named)
      end

      def list
        unlocked = SpellUnlocks.unlocked(subject).sort

        return client.emit_ooc(t('pf2e.access_none', :char => subject.name)) if unlocked.empty?

        client.emit BorderedListTemplate.new(unlocked, t('pf2e.access_title', :char => subject.name)).render
      end
    end

    # admin/unaccess <character>/spell=<spell>: takes back an unlock. A spell they already learned stays
    # learned; this only stops them learning it again.
    class PF2AdminUnaccessCmd
      include CommandHandler
      include NamesAccess

      attr_accessor :character, :kind, :name

      def parse_args
        parse_access_args
      end

      def required_args
        [ self.character, self.kind, self.name ]
      end

      def handle
        return client.emit_failure(t('pf2e.not_found')) unless subject
        return client.emit_failure(spell) if spell.is_a?(String)

        named, _details = spell

        return client.emit_failure(t('pf2e.access_not_held', :char => subject.name, :spell => named)) unless
          SpellUnlocks.unlocked?(subject, named)

        SpellUnlocks.relock!(subject, named, :by => enactor.name)

        client.emit_success t('pf2e.access_removed', :char => subject.name, :spell => named)
      end
    end
  end
end
