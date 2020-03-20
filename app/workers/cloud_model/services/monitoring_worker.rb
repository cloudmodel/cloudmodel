module CloudModel
  module Services
    class MonitoringWorker < CloudModel::Services::BaseWorker
      def write_config
      end
    
      def auto_start
        puts "        Add Monitoring to runlevel default"
        mkdir_p "#{@guest.deploy_path}/etc/systemd/system/timers.target.wants"
        @host.exec "ln -sf /etc/systemd/system/rake@.timer #{@guest.deploy_path.shellescape}/etc/systemd/system/timers.target.wants/rake@cloudmodel:monitoring:check.timer"
      end
    end
  end
end