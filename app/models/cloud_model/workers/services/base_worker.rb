module CloudModel
  module Workers
    module Services
      class BaseWorker  < CloudModel::Workers::BaseWorker

        def initialize guest, model
          @guest = guest
          @host = @guest.host
          @model = model
        end

        def guest
          @guest
        end

        def host
          @host
        end

        def mkdir_p path
          super path
          host.exec! "chown -R 100000:100000 #{path}", "failed to set owner for #{path}"
        end

        def render_to_remote template, remote_file, *param_array
          super template, remote_file, *param_array
          host.exec! "chown -R 100000:100000 #{remote_file}", "failed to set owner for #{remote_file}"
        end

        def write_config
        end

        def service_name
          @model.class.model_name.element.shellescape
        end

        def overlay_path
          "#{@guest.deploy_path.shellescape}/etc/systemd/system/#{service_name}.service.d"
        end

        def auto_restart
          false
        end

        def auto_start
          comment_sub_step "Add #{@model.class.model_name.human} to runlevel default"
          @host.exec "ln -sf /lib/systemd/system/#{service_name}.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
          if auto_restart
            mkdir_p overlay_path
            render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{overlay_path}/restart.conf"
          end
          @host.exec  "chown -R 100000:100000 #{overlay_path}"
        end

      end
    end
  end
end