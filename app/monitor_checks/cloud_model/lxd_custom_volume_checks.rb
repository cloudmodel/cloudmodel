module CloudModel
  class LxdCustomVolumeChecks < CloudModel::BaseChecks
    def initialize host, guest, lxd_custom_volume, options = {}
      puts "    [LXD Logical Volume #{lxd_custom_volume.name}]"
      @indent = 4
      @host = host
      @guest = guest
      @subject = lxd_custom_volume
      @result = @subject.lxc_show 
      
      store_check_result
    end
    
    def check_existence
      do_check :existence, 'existence of volume', warning: @result == {"error"=>"not found"}
    end
    
    def check
      check_existence
    end
  end
end