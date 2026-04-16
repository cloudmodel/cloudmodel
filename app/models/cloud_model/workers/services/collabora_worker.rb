module CloudModel
  module Workers
    module Services
      # Worker that configures the Collabora Online service inside a guest container.
      #
      # Uses `loolconfig` to disable SSL (handled by the nginx reverse proxy),
      # enable SSL termination, and optionally set the allowed WOPI host.
      class CollaboraWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          chroot! @guest.deploy_path, "loolconfig set ssl.enable false", "Failed to set collabora ssl option"
          chroot! @guest.deploy_path, "loolconfig set ssl.termination true", "Failed to set collabora termination option"
          if @model.wopi_host
            chroot! @guest.deploy_path, "loolconfig set storage.wopi.host #{@model.wopi_host}", "Failed to set collabora host option"
          end
        end

        def auto_restart
          true
        end

        def service_name
          "loolwsd"
        end
      end
    end
  end
end