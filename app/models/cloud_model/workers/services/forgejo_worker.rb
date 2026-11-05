module CloudModel
  module Workers
    module Services
      # Worker that configures the Forgejo service inside a guest container.
      #
      # Generates missing cryptographic secrets (SECRET_KEY, INTERNAL_TOKEN,
      # LFS_JWT_SECRET, oauth JWT secret) using `forgejo generate secret`,
      # saves them back to the model, renders `app.ini`, optionally uploads a
      # custom SVG logo, provisions the OIDC login source and registers the
      # Actions runners linked to the service.
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

          runners = @model.actions_enabled ? @model.actions_runners : []

          if @model.oidc? or runners.any?
            # Login sources and runners live in Forgejo's own database, so the
            # schema is brought to this release first (also the upgrade path
            # of the data volume when the release changed).
            migrate_database
          end

          config_oidc_login_source if @model.oidc?
          runners.each { |runner| register_actions_runner runner }
        end

        # Provisions (or updates) the external OIDC login source Forgejo uses to
        # let users authenticate against an external OIDC provider. The source
        # lives in Forgejo's own database, and the operation is made idempotent
        # by looking up an existing source of the same name and updating it
        # instead of adding a duplicate. Every mapping flag is passed on each
        # run (empty when unset) so a cleared field also clears the source.
        def config_oidc_login_source
          comment_sub_step "Configure OIDC login source '#{@model.oidc_name}'"

          _, list = chroot @guest.deploy_path, "#{as_forgejo} #{"#{cli} admin auth list".shellescape}"
          id = list.to_s.lines.map { |l| l.strip.split(/\t+/) }.find { |cols| cols[1] == @model.oidc_name }&.first

          common = "--name #{@model.oidc_name.shellescape}" \
            " --provider openidConnect" \
            " --key #{@model.oidc_client_id.shellescape}" \
            " --secret #{@model.oidc_client_secret.to_s.shellescape}" \
            " --auto-discover-url #{@model.oidc_auto_discovery_url.shellescape}" \
            " --skip-local-2fa=#{@model.oidc_skip_local_2fa ? 'true' : 'false'}" \
            " --group-claim-name #{@model.oidc_group_claim.to_s.shellescape}" \
            " --admin-group #{@model.oidc_admin_group.to_s.shellescape}" \
            " --restricted-group #{@model.oidc_restricted_group.to_s.shellescape}" \
            " --required-claim-name #{@model.oidc_required_claim_name.to_s.shellescape}" \
            " --required-claim-value #{@model.oidc_required_claim_value.to_s.shellescape}" \
            " --group-team-map #{@model.oidc_group_team_map.to_s.shellescape}" \
            " --group-team-map-removal=#{@model.oidc_group_team_map_removal ? 'true' : 'false'}"
          common += @model.oidc_scope_list.map { |scope| " --scopes #{scope.shellescape}" }.join

          cmd = if id
            "#{cli} admin auth update-oauth --id #{id.to_i} #{common}"
          else
            "#{cli} admin auth add-oauth #{common}"
          end

          chroot! @guest.deploy_path, "#{as_forgejo} #{cmd.shellescape}", "Failed to configure OIDC login source"
        end

        # Registers (or updates) an Actions runner with its shared secret —
        # offline, in the deploy chroot; idempotent on the Forgejo side.
        #
        # @param runner [CloudModel::Services::ForgejoRunner]
        def register_actions_runner runner
          comment_sub_step "Register Actions runner '#{runner.effective_runner_name}'"

          if runner.registration_secret.blank?
            comment_sub_step "Runner '#{runner.effective_runner_name}' has no registration secret yet (deploy it first), skipping"
            return
          end

          chroot! @guest.deploy_path, "#{as_forgejo} #{@model.runner_registration_command(runner).shellescape}", "Failed to register runner #{runner.effective_runner_name}"
        end

        def migrate_database
          comment_sub_step "Migrate forgejo database"
          chroot! @guest.deploy_path, "#{as_forgejo} #{"#{cli} migrate".shellescape}", "Failed to migrate forgejo db"
        end

        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/forgejo.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"
          super
        end

        private

        def as_forgejo
          CloudModel::Services::Forgejo.as_forgejo
        end

        def cli
          CloudModel::Services::Forgejo.cli
        end
      end
    end
  end
end
