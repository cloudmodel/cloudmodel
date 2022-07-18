module CloudModel
  module Workers
    module Services
      class RakeWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
        end

        def auto_start
          comment_sub_step "Add Rake timer to runlevel default"
          mkdir_p "#{@guest.deploy_path}/etc/systemd/system/timers.target.wants"
          render_to_remote "/cloud_model/guest/etc/systemd/system/rake.timer", "#{@guest.deploy_path}/etc/systemd/system/rake-#{@model.rake_task}.timer", 644, service: @model
          render_to_remote "/cloud_model/guest/etc/systemd/system/rake.service", "#{@guest.deploy_path}/etc/systemd/system/rake-#{@model.rake_task}.service", 644, service: @model
          @host.exec "ln -sf /etc/systemd/system/rake-#{@model.rake_task}.timer #{@guest.deploy_path.shellescape}/etc/systemd/system/timers.target.wants/"
          @host.exec "chown -R 100000:100000 #{@guest.deploy_path}/etc/systemd/system/rake-#{@model.rake_task}.service #{@guest.deploy_path}/etc/systemd/system/rake-#{@model.rake_task}.timer #{@guest.deploy_path.shellescape}/etc/systemd/system/timers.target.wants/rake-#{@model.rake_task}.timer"
         end
      end
    end
  end
end