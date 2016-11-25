module AresMUSH
  class Game
      attribute :ship_condition
  end

  module Utils
    class ConditionCmd
      include CommandHandler
      include CommandWithoutSwitches
      
      attr_accessor :condition
      
      def crack!
        self.condition = cmd.args
      end
      
      def handle
        if (self.condition != "1" && self.condition != "2" && self.condition != "3" && self.condition != "4")
           client.emit_failure "Invalid condition."
           return
        end
        Global.client_monitor.logged_in_clients.each do |c|
           c.emit "%xhAttention all hands!  The ship is now at %xrCondition #{self.condition}%xn."
           Game.master.update(ship_condition: self.condition)
        end
      end
    end
  end
end
