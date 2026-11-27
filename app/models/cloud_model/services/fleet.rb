module CloudModel
  module Services
    # Fleet device management server (osquery fleet manager) embedded in a
    # {Guest} — the Go application only.
    #
    # Fleet keeps its state in a MySQL 8 database and uses Redis for live
    # queries and caches; both come from services in the same guest: a
    # {Mysql} (Fleet does not run on MariaDB) and a {Redis}. Fleet
    # creates its own database and user in that server and runs
    # `fleet prepare db` before every start, which is what its upgrade
    # procedure asks for. Fleet speaks plain HTTP on the private network
    # (monitoring reads `/healthz` there) and is never public itself: an
    # {Nginx} service with `reverse_proxy_for http://localhost:<port>` in the
    # same guest terminates TLS and is the endpoint the agents enroll with.
    #
    # The Fleet release is part of the component name (`fleet@<version>`), so
    # bumping {#fleet_version} (or the worker default) yields a new template.
    #
    # The first administrator is created by the guest itself on the first
    # boot (`fleet_provision.service`), together with an API-only user whose
    # token is kept below {DATA_DIR} (meant to be a data volume, it also holds
    # the vulnerability feeds). On every boot the provisioning converges the
    # enroll secret, the organisation name, the server URL, Fleet's usage
    # statistics switch and the optional SAML single sign-on settings through
    # `fleetctl apply`.
    class Fleet < Base
      # @!attribute [rw] port
      #   @return [Integer] Fleet HTTP port on localhost (default: 8080)
      field :port, type: Integer, default: 8080

      # @!attribute [rw] fleet_version
      #   @return [String, nil] Fleet release to install; blank uses
      #     {CloudModel::Workers::Components::FleetComponentWorker::FLEET_VERSION}
      field :fleet_version, type: String, default: nil

      # @!attribute [rw] telemetry
      #   @return [Boolean] let Fleet send its usage statistics to the
      #     vendor (off by default; the database server has its own switch)
      field :telemetry, type: Mongoid::Boolean, default: false

      # @!attribute [rw] org_name
      #   @return [String, nil] organisation name shown in Fleet; blank uses the guest name
      field :org_name, type: String, default: nil

      # @!attribute [rw] admin_email
      #   @return [String, nil] email of the first Fleet administrator, created
      #     on the first boot with {#admin_password}
      field :admin_email, type: String, default: nil

      # @!attribute [rw] admin_password
      #   @return [String, nil] initial password of the first administrator
      #     (generated; change it after the first login)
      field :admin_password, type: String, default: nil

      # @!attribute [rw] database_password
      #   @return [String, nil] password of the Fleet database user (generated)
      field :database_password, type: String, default: nil

      # @!attribute [rw] server_private_key
      #   @return [String, nil] key Fleet encrypts secrets in its database with (generated)
      field :server_private_key, type: String, default: nil

      # @!attribute [rw] enroll_secret
      #   @return [String, nil] global enroll secret the agents present (generated)
      field :enroll_secret, type: String, default: nil

      # @!attribute [rw] sso_idp_name
      #   @return [String, nil] name of the SAML identity provider shown on the
      #     login page; SAML single sign-on is configured when this and
      #     {#sso_metadata_url} are set
      field :sso_idp_name, type: String, default: nil

      # @!attribute [rw] sso_entity_id
      #   @return [String, nil] SAML entity id of Fleet as service provider;
      #     blank uses the external hostname
      field :sso_entity_id, type: String, default: nil

      # @!attribute [rw] sso_metadata_url
      #   @return [String, nil] URL of the identity provider's SAML metadata
      field :sso_metadata_url, type: String, default: nil

      # @!attribute [rw] sso_jit_provisioning
      #   @return [Boolean] create Fleet users on their first SSO login
      field :sso_jit_provisioning, type: Mongoid::Boolean, default: true

      # @!attribute [rw] cisa_known_exploits_url
      #   @return [String, nil] where Fleet downloads CISA's catalog of known
      #     exploited vulnerabilities; blank uses Fleet's default (cisa.gov).
      #     Set it to a mirror when the host's network is refused there, e.g.
      #     CISA's own copy on GitHub (cisagov/kev-data)
      field :cisa_known_exploits_url, type: String, default: nil

      # @!attribute [rw] chrome_profiles
      #   @return [Boolean] read the Google Chrome profiles of a device's
      #     users (Fleet's `google_chrome_profiles` detail query, which maps a
      #     host to the e-mail addresses signed into Chrome). It reads every
      #     local user's profiles, not only the device owner's, so it is off
      #     by default; switching it off does not remove what Fleet stored
      #     before (`host_emails`, source `google_chrome_profiles`).
      field :chrome_profiles, type: Mongoid::Boolean, default: false

      # Fleet's built-in query behind {#chrome_profiles}, sent back as the
      # override when the switch is turned on again (an override of `null`
      # disables the query and stays until replaced).
      CHROME_PROFILES_QUERY = "SELECT email FROM google_chrome_profiles WHERE NOT ephemeral AND email <> ''".freeze

      # Provisioning token and vulnerability feeds; meant to be a data volume.
      DATA_DIR = '/var/lib/fleet'.freeze

      DATABASE_NAME = 'fleet'.freeze
      DATABASE_USER = 'fleet'.freeze

      validates :cisa_known_exploits_url, format: { with: %r{\Ahttps?://\S+\z} }, allow_blank: true
      validates :admin_email, presence: true, format: { with: /\A[^@\s]+@[^@\s]+\z/ }
      validate :guest_must_have_database_and_redis
      # root_url, api_email and the SAML entity id are built from it.
      validate :guest_must_have_external_hostname
      validate :host_arch_must_have_a_fleet_server, if: :new_record?

      def kind
        :fleet
      end

      # @return [String] the Fleet release this service runs on
      def effective_fleet_version
        fleet_version.presence || CloudModel::Workers::Components::FleetComponentWorker::FLEET_VERSION
      end

      def components_needed
        ([:"fleet@#{effective_fleet_version}"] + super).uniq
      end

      def used_ports
        [[port, :tcp]]
      end

      # @return [String] URL the agents and users reach Fleet at
      def root_url
        "https://#{guest.external_hostname}"
      end

      # @return [CloudModel::Services::Mysql, nil] the database server in the guest
      def database_service
        guest&.services&.to_a&.detect { |s| s.is_a?(CloudModel::Services::Mysql) }
      end

      # @return [Integer] port of the database server on localhost
      def database_port
        database_service&.port || 3306
      end

      # @return [CloudModel::Services::Redis, nil] the Redis in the guest
      def redis_service
        guest&.services&.to_a&.detect { |s| s.is_a?(CloudModel::Services::Redis) }
      end

      # @return [Integer] port of the Redis on localhost
      def redis_port
        redis_service&.port || 6379
      end

      # @return [String] organisation name configured in Fleet
      def effective_org_name
        org_name.presence || guest.name
      end

      # @return [String] email of the API-only provisioning user
      def api_email
        "cloudmodel-api@#{guest.external_hostname}"
      end

      # @return [Boolean] whether SAML single sign-on is configured
      def sso?
        sso_idp_name.present? && sso_metadata_url.present?
      end

      # @return [String] SAML entity id of Fleet
      def effective_sso_entity_id
        sso_entity_id.presence || guest.external_hostname
      end

      # Generates the missing secrets (database password, server key, enroll
      # secret, administrator password). Existing values are kept.
      # @return [Boolean] whether a secret was generated
      def generate_secrets
        changed = false
        {
          database_password: -> { SecureRandom.alphanumeric(32) },
          server_private_key: -> { SecureRandom.base64(32) },
          enroll_secret: -> { SecureRandom.alphanumeric(32) },
          admin_password: -> { "#{SecureRandom.alphanumeric(20)}-1aA" }
        }.each do |attr, generator|
          next if self[attr].present?
          self[attr] = generator.call
          changed = true
        end
        changed
      end

      # Settings converged by `fleetctl apply` on every boot.
      # @return [Array<Hash>] fleetctl spec documents
      def provision_specs
        config = {
          'org_info' => { 'org_name' => effective_org_name },
          'server_settings' => { 'server_url' => root_url, 'enable_analytics' => !!telemetry },
          'features' => { 'detail_query_overrides' => { 'google_chrome_profiles' => chrome_profiles ? CHROME_PROFILES_QUERY : nil } }
        }
        config['sso_settings'] = if sso?
          {
            'enable_sso' => true,
            'idp_name' => sso_idp_name,
            'entity_id' => effective_sso_entity_id,
            'metadata_url' => sso_metadata_url,
            'enable_jit_provisioning' => !!sso_jit_provisioning
          }
        else
          { 'enable_sso' => false }
        end

        [
          { 'apiVersion' => 'v1', 'kind' => 'enroll_secret', 'spec' => { 'secrets' => [{ 'secret' => enroll_secret.to_s }] } },
          { 'apiVersion' => 'v1', 'kind' => 'config', 'spec' => config }
        ]
      end

      def stop_timeout
        60
      end

      def ready?
        monitoring_http_get("http://#{guest.private_address}:#{port}/healthz").code == '200'
      rescue Exception
        false
      end

      # Health from `/healthz`, which checks the database and Redis.
      def service_status
        res = monitoring_http_get("http://#{guest.private_address}:#{port}/healthz")
        if res.code == '200'
          { healthy: true }
        else
          { key: :not_healthy, error: "healthz answered #{res.code}: #{res.body.to_s.strip[0, 200]}", severity: :critical }
        end
      rescue Exception => e
        { key: :not_reachable, error: "#{e.class}\n\n#{e}", severity: :critical }
      end

      private

      def host_arch_must_have_a_fleet_server
        arch = guest&.host&.arch
        return if arch.blank? || CloudModel::Workers::Components::FleetComponentWorker::SERVER_ARCHES.include?(arch)

        errors.add :base, :fleet_needs_server_arch, arch: arch, arches: CloudModel::Workers::Components::FleetComponentWorker::SERVER_ARCHES.join(', ')
      end

      def guest_must_have_database_and_redis
        return unless guest

        errors.add :base, :fleet_needs_mysql unless database_service
        errors.add :base, :fleet_needs_redis unless redis_service
      end

      def guest_must_have_external_hostname
        return unless guest
        errors.add :base, :fleet_needs_external_hostname if guest.external_hostname.blank?
      end
    end
  end
end
