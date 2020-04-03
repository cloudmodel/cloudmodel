module CloudModel
  module Monitoring
    class GuestChecks < CloudModel::Monitoring::BaseChecks
      include CloudModel::Monitoring::Mixins::SysinfoChecksMixin
      
      def indent_size
        2
      end
    
      def aquire_data
        {
          system: @subject.system_info,
          lxc: @subject.lxc_info
        }
      end
          
      def check
        check_system_info
      end
    end
  end
end