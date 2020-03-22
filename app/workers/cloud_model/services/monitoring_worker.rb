module CloudModel
  module Services
    class MonitoringWorker < CloudModel::Services::BaseWorker
      def write_config
      end
    
      def auto_start
        puts "        Write Monitoring systemd"
        render_to_remote "/cloud_model/guest/etc/systemd/system/monitoring.service", "#{@guest.deploy_path}/etc/systemd/system/monitoring.service", guest: @guest, model: @model      
        chroot! @guest.deploy_path, "ln -s /etc/systemd/system/monitoring.service /etc/systemd/system/multi-user.target.wants/monitoring.service", "Failed to enable monitoring service" 
      end
    end
  end
end