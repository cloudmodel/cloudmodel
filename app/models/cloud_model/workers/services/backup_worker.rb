module CloudModel
  module Workers
    module Services
      class BackupWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
        end

        def auto_start
          comment_sub_step "Add Rake timer to runlevel default"

          rake_service = CloudModel::Services::Rake.new(
            rake_task: 'cloudmodel:guest:backup_all',
            rake_timer_on_boot: true,
            rake_timer_on_boot_sec: 900,
            rake_timer_on_calendar: true,
            rake_timer_on_calendar_val: "00:00",
            rake_timer_accuracy_sec: 600,
            rake_timer_persistent: false,
          )

          mkdir_p "#{@guest.deploy_path}/etc/systemd/system/timers.target.wants"
          render_to_remote "/cloud_model/guest/etc/systemd/system/rake.timer", "#{@guest.deploy_path}/etc/systemd/system/rake-#{rake_service.rake_task}.timer", 644, service: rake_service
          render_to_remote "/cloud_model/guest/etc/systemd/system/rake.service", "#{@guest.deploy_path}/etc/systemd/system/rake-#{rake_service.rake_task}.service", 644, service: rake_service
          @host.exec "ln -sf /etc/systemd/system/rake-#{rake_service.rake_task}.timer #{@guest.deploy_path.shellescape}/etc/systemd/system/timers.target.wants/"
          @host.exec "chown -R 100000:100000 #{@guest.deploy_path}/etc/systemd/system/rake-#{rake_service.rake_task}.service #{@guest.deploy_path}/etc/systemd/system/rake-#{rake_service.rake_task}.timer #{@guest.deploy_path.shellescape}/etc/systemd/system/timers.target.wants/rake-#{rake_service.rake_task}.timer"
        end
      end
    end
  end
end