module CloudModel
  module Workers
    module Services
      # Worker that configures the Forgejo service inside a guest container.
      #
      # Generates missing cryptographic secrets (SECRET_KEY, INTERNAL_TOKEN,
      # LFS_JWT_SECRET, oauth JWT secret) using `forgejo generate secret`,
      # saves them back to the model, renders `app.ini`, and optionally
      # uploads a custom SVG logo.
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

          if @model.logo_svg
            dir_name = "/var/lib/forgejo/custom/public/assets/img/"
            mkdir_p "#{@guest.deploy_path}#{dir_name}"

            upload_to_guest @model.logo_svg, "#{dir_name}logo.svg"
            upload_to_guest @model.logo_svg, "#{dir_name}favicon.svg"

            # forgejo serves these assets as its own user.
            chroot! @guest.deploy_path, "chown -R forgejo:forgejo /var/lib/forgejo/custom && chmod 644 #{dir_name}logo.svg #{dir_name}favicon.svg", "Failed to set logo ownership"
          end

          config_oidc_login_source if @model.oidc?
        end

        # Provisions (or updates) the external OIDC login source Forgejo uses to
        # let users authenticate against an external OIDC provider. The source lives in
        # Forgejo's own database, so the schema is migrated first and the
        # operation is made idempotent by looking up an existing source of the
        # same name and updating it instead of adding a duplicate.
        def config_oidc_login_source
          comment_sub_step "Configure OIDC login source '#{@model.oidc_name}'"

          as_forgejo = "su -s /bin/bash forgejo -c"
          cli = "GITEA_WORK_DIR=/var/lib/forgejo forgejo --config /etc/forgejo/app.ini"

          chroot! @guest.deploy_path, "#{as_forgejo} #{"#{cli} migrate".shellescape}", "Failed to migrate forgejo db"

          _, list = chroot @guest.deploy_path, "#{as_forgejo} #{"#{cli} admin auth list".shellescape}"
          id = list.to_s.lines.map { |l| l.strip.split(/\t+/) }.find { |cols| cols[1] == @model.oidc_name }&.first

          common = "--name #{@model.oidc_name.shellescape}" \
            " --provider openidConnect" \
            " --key #{@model.oidc_client_id.shellescape}" \
            " --secret #{@model.oidc_client_secret.to_s.shellescape}" \
            " --auto-discover-url #{@model.oidc_auto_discovery_url.shellescape}"

          cmd = if id
            "#{cli} admin auth update-oauth --id #{id.to_i} #{common}"
          else
            "#{cli} admin auth add-oauth #{common}"
          end

          chroot! @guest.deploy_path, "#{as_forgejo} #{cmd.shellescape}", "Failed to configure OIDC login source"
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