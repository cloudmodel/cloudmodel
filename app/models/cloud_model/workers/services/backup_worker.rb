module CloudModel
  module Workers
    module Services
      class BackupWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
        end
    
        def auto_start
          puts "        Add Backup to runlevel default"
          mkdir_p "#{@guest.deploy_path}/etc/systemd/system/timers.target.wants"
          @host.exec "ln -sf /etc/systemd/system/rake@.timer #{@guest.deploy_path.shellescape}/etc/systemd/system/timers.target.wants/rake@cloudmodel:guest:backup_all.timer"
        end
      end
    end
  end
end