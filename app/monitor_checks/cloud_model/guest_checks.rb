module CloudModel
  class GuestChecks < CloudModel::BaseChecks
    include CloudModel::Mixins::SysinfoChecksMixin

    def initialize host, guest, options = {}
      puts "  [Guest #{guest.name}]"
      @indent = 2
      @host = host
      @subject = guest
      
      if options[:cached]
        @result = @subject.monitoring_last_check_result
      else
        print "    * Acqire data ..."
        @result = {
          system: @subject.system_info,
          lxc: @subject.lxc_info
        }
        puts "[Done]"
      
        store_check_result
      end
    end
    
    def check
      check_system_info
    end
  end
end