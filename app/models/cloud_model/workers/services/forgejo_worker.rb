module CloudModel
  module Workers
    module Services
      # Worker that configures the Forgejo service inside a guest container.
      #
      # Generates missing cryptographic secrets (SECRET_KEY, INTERNAL_TOKEN,
      # LFS_JWT_SECRET, oauth JWT secret) using `forgejo generate secret`,
      # saves them back to the model, renders `app.ini`, optionally uploads a
      # custom SVG logo and renders the provisioning script that converges the
      # OIDC login source and the Actions runners.
      #
      # The login source and the runners live in Forgejo's database on the
      # data volume, which is not mounted into the deploy chroot (custom
      # volumes are attached when the container starts). Writing them here
      # would land in a database on the root image that the volume shadows at
      # run time, so they are applied by `forgejo_provision.service`: a oneshot
      # unit that waits for Forgejo to answer, then runs the idempotent CLI
      # calls as the forgejo user — on every boot, so a redeploy with changed
      # fields converges the instance.
      class ForgejoWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          comment_sub_step "Config forgejo"

          @model.secret_key ||= chroot!(@guest.deploy_path, "forgejo generate secret SECRET_KEY", "Failed to generate SECRET_KEY")
          @model.internal_token ||= chroot!(@guest.deploy_path, "forgejo generate secret INTERNAL_TOKEN", "Failed to generate INTERNAL_TOKEN")
          @model.lfs_jwt_secret ||= chroot!(@guest.deploy_path, "forgejo generate secret LFS_JWT_SECRET", "Failed to generate LFS_JWT_SECRET")
          @model.oauth_jwt_secret ||= chroot!(@guest.deploy_path, "forgejo generate secret JWT_SECRET", "Failed to generate JWT_SECRET")
          @model.save

          render_to_guest "/cloud_model/guest/etc/forgejo/app.ini", "/etc/forgejo/app.ini", 0600, guest: @guest, model: @model
          # app.ini holds the runtime config the forgejo user must read (the
          # service and every `forgejo` CLI call run as that user).
          chroot! @guest.deploy_path, "chown forgejo:forgejo /etc/forgejo/app.ini && chmod 640 /etc/forgejo/app.ini", "Failed to set app.ini ownership"

          # Branding lives in the custom path on the root image (see
          # Services::Forgejo::CUSTOM_PATH): the data volume is not mounted
          # during the deploy and would shadow anything placed under the work dir.
          custom = CloudModel::Services::Forgejo::CUSTOM_PATH
          mkdir_p "#{@guest.deploy_path}#{custom}"
          if @model.logo_svg
            dir_name = "#{custom}/public/assets/img/"
            mkdir_p "#{@guest.deploy_path}#{dir_name}"

            upload_to_guest @model.logo_svg, "#{dir_name}logo.svg"
            upload_to_guest @model.logo_svg, "#{dir_name}favicon.svg"
          end
          # forgejo serves these assets as its own user.
          chroot! @guest.deploy_path, "chown -R forgejo:forgejo #{custom} && find #{custom} -type f -exec chmod 644 {} +", "Failed to set custom path ownership"

          write_provision_script
        end

        # Script run by forgejo_provision.service after Forgejo is up: login
        # source (add or update by name) and runner registrations. Carries the
        # client secret and the runner secrets, hence root-only.
        def write_provision_script
          runners = @model.actions_enabled ? @model.actions_runners.select { |r| r.registration_secret.present? } : []
          comment_sub_step "Render provisioning script (login source: #{@model.oidc? ? @model.oidc_name : 'none'}, runners: #{runners.size})"

          render_to_guest "/cloud_model/guest/etc/forgejo/provision.sh", "/etc/forgejo/provision.sh", 0700, guest: @guest, model: @model, runners: runners
          chroot! @guest.deploy_path, "chown root:root /etc/forgejo/provision.sh && chmod 700 /etc/forgejo/provision.sh", "Failed to set provision script ownership"
        end

        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/forgejo.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"

          comment_sub_step "Add forgejo provisioning to runlevel default"
          render_to_remote "/cloud_model/guest/etc/systemd/system/forgejo_provision.service", "#{@guest.deploy_path.shellescape}/etc/systemd/system/forgejo_provision.service", 0644
          @host.exec "ln -sf /etc/systemd/system/forgejo_provision.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"

          super
        end
      end
    end
  end
end
