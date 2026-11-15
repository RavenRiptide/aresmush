module AresMUSH
  module Pf2egear

    # `gear/attach <shield number>=<weapon number>`: attaches a shield boss or shield spikes to a shield.
    # `gear/detach <shield number>`: takes it off again (`Pf2egear::ShieldAttach`).
    class PF2GearAttachCmd
      include CommandHandler

      attr_accessor :shield, :weapon

      def parse_args
        if cmd.switch == 'attach'
          args = cmd.parse_args(ArgParser.arg1_equals_arg2)
          self.shield = integer_arg(args.arg1)
          self.weapon = integer_arg(args.arg2)
        else
          self.shield = integer_arg(cmd.args)
        end
      end

      def required_args
        cmd.switch == 'attach' ? [ self.shield, self.weapon ] : [ self.shield ]
      end

      def handle
        running = PF2Encounter.running_for(enactor).first

        return client.emit_failure(t('pf2egear.attach_in_encounter', :id => running.id)) if running

        done = cmd.switch == 'attach' ? ShieldAttach.attach(enactor, self.shield, self.weapon) : ShieldAttach.detach(enactor, self.shield)

        return if Pf2e::CharState.emit_error!(client, done)

        key = cmd.switch == 'attach' ? 'pf2egear.attached_ok' : 'pf2egear.detached_ok'
        client.emit_success t(key, :weapon => done.state['weapon'], :shield => done.state['shield'])
      end
    end
  end
end
