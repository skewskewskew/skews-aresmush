module AresMUSH

  module Events
    class EventDeleteCmd
      include CommandHandler
      
      attr_accessor :num

      def parse_args
        self.num = integer_arg(cmd.args)
      end
      
      def required_args
        {
          args: [ self.num ],
          help: 'events'
        }
      end
      
      def handle
        Events.with_an_event(self.num, client, enactor) do |event| 
          
           if (Events.can_manage_events?(enactor) || enactor == event.character)
             event.delete
             client.emit_success t('events.event_deleted')
           else
             client.emit_failure t('dispatcher.not_allowed')
           end 
        end
      end
    end
  end
end
