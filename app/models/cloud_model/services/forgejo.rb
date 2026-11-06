module CloudModel
  module Services
    # Forgejo self-hosted Git service embedded in a {Guest}.
    #
    # Deploys a Forgejo instance (a lightweight Gitea fork) for Git repository
    # hosting. Health status is derived from the Prometheus metrics endpoint at
    # `/metrics`. All secret material (secret key, tokens, JWT secrets) is
    # stored as model fields and rendered into the Forgejo configuration at
    # deploy time.
    #
    # The Forgejo release is part of the component name (`forgejo@<version>`),
    # so bumping {#forgejo_version} (or the worker default) yields a new guest
    # template instead of silently reusing the one built for the old release.
    #
    # Login can be restricted to an external OIDC provider whose `groups`
    # claim is mapped onto Forgejo roles and teams (administrators,
    # restricted users, organisation teams, required claim to limit who may
    # log in). Forgejo Actions runners ({ForgejoRunner}) reference this
    # service and are registered with their shared secret on every deploy.
    #
    # Backups: the data volume (`var/lib/forgejo`) is snapshotted by the
    # volume backup; in addition the service backup takes a `forgejo dump`
    # (database, repositories, LFS, config) and stores it in the backup
    # directory.
    class Forgejo < Base
      include CloudModel::Mixins::BackupTools

      # @!attribute [rw] port
      #   @return [Integer] Forgejo HTTP port (default: 3000)
      field :port, type: Integer, default: 3000

      # @!attribute [rw] forgejo_version
      #   @return [String, nil] Forgejo release to install; blank uses the
      #     component worker default ({CloudModel::Workers::Components::ForgejoComponentWorker::FORGEJO_VERSION})
      field :forgejo_version, type: String, default: nil

      # @!attribute [rw] default_theme
      #   @return [String] Forgejo UI theme name (default: `"forgejo-auto"`)
      field :default_theme, type: String, default: "forgejo-auto"

      # @!attribute [rw] logo_svg
      #   @return [String, nil] custom SVG logo markup to override the default Forgejo logo
      field :logo_svg, type: String, default: nil

      # @!attribute [rw] secret_key
      #   @return [String, nil] global secret key for CSRF and session signing
      field :secret_key, type: String, default: nil

      # @!attribute [rw] internal_token
      #   @return [String, nil] JWT token for internal API calls between Forgejo components
      field :internal_token, type: String, default: nil

      # @!attribute [rw] lfs_jwt_secret
      #   @return [String, nil] secret used to sign Git LFS JWT tokens
      field :lfs_jwt_secret, type: String, default: nil

      # @!attribute [rw] oauth_jwt_secret
      #   @return [String, nil] secret used to sign OAuth2 JWT tokens
      field :oauth_jwt_secret, type: String, default: nil

      # @!attribute [rw] external_login_only
      #   @return [Boolean] the OIDC login source is the only way in: the
      #     built-in sign-in flow, HTTP basic auth with passwords and local
      #     registration are switched off (local admins remain manageable
      #     with the CLI). Only honoured when {#oidc?} is true.
      field :external_login_only, type: Mongoid::Boolean, default: false

      # @!attribute [rw] enable_openid_signin
      #   @return [Boolean] allow signing in via legacy OpenID 2.0 providers
      field :enable_openid_signin, type: Mongoid::Boolean, default: false

      # @!attribute [rw] enable_openid_signup
      #   @return [Boolean] allow self-registration via legacy OpenID 2.0 providers
      field :enable_openid_signup, type: Mongoid::Boolean, default: false

      # @!attribute [rw] oidc_name
      #   @return [String, nil] name of the OIDC login source (e.g. `"sso"`);
      #     when blank no external login source is provisioned
      field :oidc_name, type: String, default: nil

      # @!attribute [rw] oidc_auto_discovery_url
      #   @return [String, nil] OIDC `.well-known/openid-configuration` URL of the provider
      field :oidc_auto_discovery_url, type: String, default: nil

      # @!attribute [rw] oidc_client_id
      #   @return [String, nil] OAuth2 client id registered with the provider
      field :oidc_client_id, type: String, default: nil

      # @!attribute [rw] oidc_client_secret
      #   @return [String, nil] OAuth2 client secret registered with the provider
      field :oidc_client_secret, type: String, default: nil

      # @!attribute [rw] oidc_scopes
      #   @return [String] space separated scopes requested from the provider
      field :oidc_scopes, type: String, default: "openid profile email groups"

      # @!attribute [rw] oidc_skip_local_2fa
      #   @return [Boolean] do not ask for Forgejo's own second factor after a
      #     login through this source (the provider already enforced it)
      field :oidc_skip_local_2fa, type: Mongoid::Boolean, default: false

      # @!attribute [rw] oidc_auto_registration
      #   @return [Boolean] create a Forgejo account on the first login through
      #     the source; off means unknown users are sent to the link-account page
      field :oidc_auto_registration, type: Mongoid::Boolean, default: true

      # @!attribute [rw] oidc_account_linking
      #   @return [String] how an OIDC identity meets an existing local account:
      #     `disabled`, `login` (link after a local login) or `auto` (by email)
      field :oidc_account_linking, type: String, default: "login"

      # @!attribute [rw] oidc_username_source
      #   @return [String] where the Forgejo user name of an auto-registered
      #     account comes from: `nickname` (preferred_username claim), `email`
      #     (local part) or `userid` (subject)
      field :oidc_username_source, type: String, default: "nickname"

      # @!attribute [rw] oidc_group_claim
      #   @return [String, nil] claim carrying the user's groups (e.g. `"groups"`)
      field :oidc_group_claim, type: String, default: "groups"

      # @!attribute [rw] oidc_admin_group
      #   @return [String, nil] group whose members become site administrators
      field :oidc_admin_group, type: String, default: nil

      # @!attribute [rw] oidc_restricted_group
      #   @return [String, nil] group whose members become restricted users
      field :oidc_restricted_group, type: String, default: nil

      # @!attribute [rw] oidc_required_claim_name
      #   @return [String, nil] claim that must be present to log in (e.g. `"groups"`)
      field :oidc_required_claim_name, type: String, default: nil

      # @!attribute [rw] oidc_required_claim_value
      #   @return [String, nil] value the required claim must carry (for list
      #     claims such as `groups`: must contain)
      field :oidc_required_claim_value, type: String, default: nil

      # @!attribute [rw] oidc_group_team_map
      #   @return [String, nil] JSON mapping groups to organisation teams, e.g.
      #     `{"developers": {"myorg": ["developers"]}}`
      field :oidc_group_team_map, type: String, default: nil

      # @!attribute [rw] oidc_group_team_map_removal
      #   @return [Boolean] also remove users from mapped teams when the group
      #     disappears from their claims
      field :oidc_group_team_map_removal, type: Mongoid::Boolean, default: false

      # @!attribute [rw] mailer_enabled
      #   @return [Boolean] send mail through the guest's sendmail (msmtp relay)
      field :mailer_enabled, type: Mongoid::Boolean, default: true

      # @!attribute [rw] mail_from
      #   @return [String, nil] sender address; blank uses `forgejo@<external hostname>`
      field :mail_from, type: String, default: nil

      # @!attribute [rw] packages_enabled
      #   @return [Boolean] enable the package registry (container images, gems, npm, …)
      field :packages_enabled, type: Mongoid::Boolean, default: true

      # @!attribute [rw] actions_enabled
      #   @return [Boolean] enable Forgejo Actions (workflows run on registered {ForgejoRunner}s)
      field :actions_enabled, type: Mongoid::Boolean, default: true

      # @!attribute [rw] actions_default_url
      #   @return [String] base URL for relative `uses:` references in workflows
      field :actions_default_url, type: String, default: "https://data.forgejo.org"

      ACCOUNT_LINKING_MODES = %w[disabled login auto].freeze
      USERNAME_SOURCES = %w[nickname email userid].freeze

      validates :oidc_account_linking, inclusion: { in: ACCOUNT_LINKING_MODES }
      validates :oidc_username_source, inclusion: { in: USERNAME_SOURCES }
      validate :oidc_group_team_map_must_be_json

      # @return [Boolean] whether an external OIDC login source should be configured
      def oidc?
        oidc_name.present? && oidc_auto_discovery_url.present? && oidc_client_id.present?
      end

      # @return [Boolean] whether local sign-in is switched off in favour of the OIDC source
      def external_login_only?
        external_login_only && oidc?
      end

      # @return [Array<String>] the scopes requested from the OIDC provider
      def oidc_scope_list
        oidc_scopes.to_s.split(/[\s,]+/).reject(&:blank?).uniq
      end

      # @return [String] the Forgejo release this service runs on
      def effective_forgejo_version
        forgejo_version.presence || CloudModel::Workers::Components::ForgejoComponentWorker::FORGEJO_VERSION
      end

      # @return [String] sender address for notification mails
      def effective_mail_from
        mail_from.presence || "forgejo@#{guest.external_hostname}"
      end

      def kind
        :forgejo
      end

      # Forgejo is a self-contained authenticated web application (its own
      # session/CSRF/JWT secrets), so it may be exposed to public networks.
      def allow_public_service?
        true
      end

      def components_needed
        ([:"forgejo@#{effective_forgejo_version}"] + super).uniq
      end

      def used_ports
        [[port, :tcp]]
      end

      # @return [String] base URL runners and users reach this instance at
      def root_url
        "https://#{guest.external_hostname}/"
      end

      # Actions runners ({ForgejoRunner} services, usually in other guests) that
      # register with this instance.
      #
      # @return [Array<CloudModel::Services::ForgejoRunner>]
      def actions_runners
        return [] if new_record?

        CloudModel::Guest.where("services._type" => "CloudModel::Services::ForgejoRunner", "services.forgejo_service_id" => id.to_s).flat_map do |g|
          g.services.select { |s| s.is_a?(CloudModel::Services::ForgejoRunner) && s.forgejo_service_id == id.to_s }
        end
      end

      # Custom path (branding, templates) on the root image: everything under
      # the work dir lives on the data volume, which the deploy cannot write.
      CUSTOM_PATH = "/etc/forgejo/custom".freeze

      # Forgejo CLI as argv, run with the deployed config, work dir and custom path.
      # @return [Array<String>]
      def self.cli_argv
        %W[env GITEA_WORK_DIR=/var/lib/forgejo GITEA_CUSTOM=#{CUSTOM_PATH} forgejo --config /etc/forgejo/app.ini]
      end

      # Runs a CLI argv as the forgejo user without an inner shell (one level
      # of quoting, whatever the values contain).
      # @param argv [Array<String>]
      # @return [String] shell command line
      def self.as_forgejo(argv)
        Shellwords.join(%w[runuser -u forgejo --] + argv)
      end

      # Flags of the OIDC login source (without the add/update verb). Every
      # mapping flag is present, empty when unset, so a cleared field clears
      # the source on the next provisioning run.
      # @return [Array<String>]
      def oidc_login_source_flags
        flags = [
          '--name', oidc_name.to_s,
          '--provider', 'openidConnect',
          '--key', oidc_client_id.to_s,
          '--secret', oidc_client_secret.to_s,
          '--auto-discover-url', oidc_auto_discovery_url.to_s,
          "--skip-local-2fa=#{oidc_skip_local_2fa ? 'true' : 'false'}",
          '--group-claim-name', oidc_group_claim.to_s,
          '--admin-group', oidc_admin_group.to_s,
          '--restricted-group', oidc_restricted_group.to_s,
          '--required-claim-name', oidc_required_claim_name.to_s,
          '--required-claim-value', oidc_required_claim_value.to_s,
          '--group-team-map', oidc_group_team_map.to_s,
          "--group-team-map-removal=#{oidc_group_team_map_removal ? 'true' : 'false'}"
        ]
        oidc_scope_list.each { |scope| flags += ['--scopes', scope] }
        flags
      end

      # CLI argv that registers or updates a runner with its shared secret;
      # idempotent on the Forgejo side.
      #
      # @param runner [CloudModel::Services::ForgejoRunner]
      # @return [Array<String>]
      def runner_registration_argv(runner)
        argv = self.class.cli_argv + ['forgejo-cli', 'actions', 'register',
          '--name', runner.effective_runner_name,
          '--labels', runner.label_names.join(','),
          '--secret', runner.registration_secret.to_s]
        argv += ['--scope', runner.scope] if runner.scope.present?
        argv
      end

      # @param runner [CloudModel::Services::ForgejoRunner]
      # @return [String] shell command (as the forgejo user)
      def runner_registration_command(runner)
        self.class.as_forgejo runner_registration_argv(runner)
      end

      # Registers a runner on the running instance (via `lxc exec`), so a newly
      # deployed runner can connect without redeploying this service.
      #
      # @param runner [CloudModel::Services::ForgejoRunner]
      # @return [String] command output
      # @raise [RuntimeError] when the registration fails
      def register_actions_runner!(runner)
        guest.exec! runner_registration_command(runner), "Failed to register runner #{runner.effective_runner_name}"
      end

      def backupable?
        true
      end

      # The data volume holding database, repositories, LFS and packages.
      def backup_data_mount_point
        'var/lib/forgejo'
      end

      # Service-level backup: a `forgejo dump` (zip with database, repositories,
      # LFS, custom files and app.ini), taken inside the guest as the forgejo
      # user, pulled to the host and fetched into the backup directory.
      # @return [Boolean]
      def backup
        return false unless has_backups

        timestamp = Time.now.strftime "%Y%m%d%H%M%S"
        target = "#{backup_directory}/#{timestamp}"
        guest_file = "/var/lib/forgejo/forgejo-dump-#{timestamp}.zip"
        host_file = "/tmp/#{guest.name}-forgejo-dump-#{timestamp}.zip"

        FileUtils.mkdir_p target

        success, output = guest.exec self.class.as_forgejo(self.class.cli_argv + ['dump', '--type', 'zip', '--file', guest_file])
        unless success
          CloudModel.backup_log "forgejo dump failed: #{output.to_s.strip.lines.last.to_s.strip}"
          FileUtils.rm_rf target
          return false
        end

        guest.host.exec! "lxc file pull #{guest.current_lxd_container.name.shellescape}#{guest_file} #{host_file.shellescape}", "Failed to pull forgejo dump from guest"
        guest.host.sftp.download! host_file, "#{target}/forgejo-dump.zip"

        FileUtils.rm_f "#{backup_directory}/latest"
        # Relative link: survives Capistrano release pruning.
        FileUtils.ln_s timestamp, "#{backup_directory}/latest"
        record_successful_backup
        cleanup_backups

        true
      rescue Exception => e
        CloudModel.backup_log "forgejo dump failed: #{e.message}"
        FileUtils.rm_rf target
        false
      ensure
        guest.exec "rm -f #{guest_file.shellescape}" rescue nil
        guest.host.exec "rm -f #{host_file.shellescape}" rescue nil
      end

      # Restoring a dump is a manual procedure (`forgejo restore` does not
      # exist; the zip is unpacked into a stopped instance), see the Forgejo
      # backup documentation.
      def restore timestamp='latest'
        raise CloudModel::BackupError, "Forgejo dumps are restored by hand: unpack #{backup_directory}/#{timestamp}/forgejo-dump.zip into a stopped instance"
      end

      # Git pushes in flight finish within seconds; the longest part is
      # Forgejo flushing its queues.
      def stop_timeout
        60
      end

      def ready?
        monitoring_http_get("http://#{guest.private_address}:#{port}/api/healthz").code == '200'
      rescue Exception
        false
      end

      def service_status
        uri = URI("http://#{guest.private_address}:#{port}/metrics")

        data = {}

        begin
          res = nil

          Net::HTTP.start(uri.host, uri.port,
            :use_ssl => uri.scheme == 'https',
            :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

            req = Net::HTTP::Get.new uri.request_uri

            res = http.request req
          end
        rescue Exception => e
           return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        end

        if res.code == '404'
          return {key: :not_found, error: "Metrics not found, but server answering", severity: :warning}
        end

        begin
          res.body.lines.each do |line|
            if line =~ /^\#/
            else
              key, value = line.split(' ')
              data[key] = value
            end
          end
        rescue Exception => e
          {key: :not_parsable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        end

        data
      end

      private

      def oidc_group_team_map_must_be_json
        return if oidc_group_team_map.blank?

        parsed = JSON.parse(oidc_group_team_map)
        errors.add :oidc_group_team_map, :invalid unless parsed.is_a?(Hash)
      rescue JSON::ParserError
        errors.add :oidc_group_team_map, :invalid
      end
    end
  end
end
