module CloudModel
  module Workers
    module Services
      class RakeWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
        end

        def auto_start
          render_to_remote "/cloud_model/guest/etc/systemd/system/rake.service", "#{@guest.deploy_path}/etc/systemd/system/rake-#{@model.rake_task}.service", 644, service: @model

          case @model.rake_mode
          when 'restart', 'single'
            auto_start_service
          else
            auto_start_timer
          end
        end

        private

        def auto_start_service
          comment_sub_step "Add Rake service to runlevel default"
          mkdir_p "#{@guest.deploy_path}/etc/systemd/system/multi-user.target.wants"
          @host.exec "ln -sf /etc/systemd/system/rake-#{@model.rake_task.shellescape}.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"

          if @model.rake_restart_on_touch
            render_to_remote "/cloud_model/guest/etc/systemd/system/rake_restart.path", "#{@guest.deploy_path}/etc/systemd/system/rake-restart-#{@model.rake_task}.path", 644, service: @model
            render_to_remote "/cloud_model/guest/etc/systemd/system/rake_restart.service", "#{@guest.deploy_path}/etc/systemd/system/rake-restart-#{@model.rake_task}.service", 644, service: @model
            @host.exec "ln -sf /etc/systemd/system/rake-restart-#{@model.rake_task.shellescape}.path #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
            @host.exec "chown -R 100000:100000 #{@guest.deploy_path}/etc/systemd/system/rake-restart-#{@model.rake_task.shellescape}.path #{@guest.deploy_path}/etc/systemd/system/rake-restart-#{@model.rake_task.shellescape}.service"
          end

          @host.exec "chown -R 100000:100000 #{@guest.deploy_path}/etc/systemd/system/rake-#{@model.rake_task.shellescape}.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/rake-#{@model.rake_task.shellescape}.service"
        end

        def auto_start_timer
          comment_sub_step "Add Rake timer to runlevel default"
          mkdir_p "#{@guest.deploy_path}/etc/systemd/system/timers.target.wants"
          render_to_remote "/cloud_model/guest/etc/systemd/system/rake.timer", "#{@guest.deploy_path}/etc/systemd/system/rake-#{@model.rake_task}.timer", 644, service: @model
          @host.exec "ln -sf /etc/systemd/system/rake-#{@model.rake_task.shellescape}.timer #{@guest.deploy_path.shellescape}/etc/systemd/system/timers.target.wants/"
          @host.exec "chown -R 100000:100000 #{@guest.deploy_path}/etc/systemd/system/rake-#{@model.rake_task.shellescape}.service #{@guest.deploy_path}/etc/systemd/system/rake-#{@model.rake_task.shellescape}.timer #{@guest.deploy_path.shellescape}/etc/systemd/system/timers.target.wants/rake-#{@model.rake_task.shellescape}.timer"
        end
      end
    end
  end
end
