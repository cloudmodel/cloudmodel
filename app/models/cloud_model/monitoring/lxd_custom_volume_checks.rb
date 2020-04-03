module CloudModel
  module Monitoring
    class LxdCustomVolumeChecks < CloudModel::Monitoring::BaseChecks    
      def indent_size
        4
      end
      
      def aquire_data
        @subject.lxc_show 
      end
      
      def check_existence
        do_check :existence, 'existence of volume', warning: data == {"error"=>"not found"}
      end
    
      def check
        check_existence
      end
    end
  end
end