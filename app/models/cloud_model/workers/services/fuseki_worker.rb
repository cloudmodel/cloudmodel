module CloudModel
  module Workers
    module Services
      class FusekiWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          comment_sub_step "Write Fuseki config"
          install_path = "#{@guest.deploy_path}/opt"
          config_path = "#{@guest.deploy_path}/etc/fuseki"

          mkdir_p "#{config_path}"
          render_to_remote "/cloud_model/guest/etc/fuseki/shiro.ini", "#{@guest.deploy_path}/etc/fuseki/shiro.ini", 0644, guest: @guest, model: @model
          render_to_remote "/cloud_model/guest/etc/systemd/system/fuseki.service", "#{@guest.deploy_path}/etc/systemd/system/fuseki.service", 0755, guest: @guest, model: @model
        end

        def service_name
          "fuseki"
        end
      end
    end
  end
end