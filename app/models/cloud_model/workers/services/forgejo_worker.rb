module CloudModel
  module Workers
    module Services
      class ForgejoWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          comment_sub_step "Config forgejo"

          secrets = {}

          @model.secret_key ||= chroot!(@guest.deploy_path, "forgejo generate secret SECRET_KEY", "Failed to generate SECRET_KEY")
          @model.internal_token ||= chroot!(@guest.deploy_path, "forgejo generate secret INTERNAL_TOKEN", "Failed to generate INTERNAL_TOKEN")
          @model.lfs_jwt_secret ||= chroot!(@guest.deploy_path, "forgejo generate secret LFS_JWT_SECRET", "Failed to generate LFS_JWT_SECRET")
          @model.oauth_jwt_secret ||= chroot!(@guest.deploy_path, "forgejo generate secret JWT_SECRET", "Failed to generate JWT_SECRET")
          @model.save

          render_to_guest "/cloud_model/guest/etc/forgejo/app.ini", "/etc/forgejo/app.ini", 0600, guest: @guest, model: @model, secrets: secrets

          if @model.logo_svg
            dir_name = "/var/lib/forgejo/custom/public/assets/img/"
            mkdir_p "#{@guest.deploy_path}#{dir_name}"

            upload_to_guest @model.logo_svg, "#{dir_name}logo.svg"
            upload_to_guest @model.logo_svg, "#{dir_name}favicon.svg"
          end
        end

        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/forgejo.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"
          super
        end
      end
    end
  end
end