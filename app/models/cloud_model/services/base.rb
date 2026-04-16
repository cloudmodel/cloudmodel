module CloudModel
  module Services
    # Abstract base class for all services embedded in a {CloudModel::Guest}.
    #
    # Services are Mongoid embedded documents stored inside a guest's `services`
    # array. Each concrete subclass (e.g. {Nginx}, {Mongodb}, {Rake}) represents
    # one running daemon or headless process inside the LXD container.
    #
    # The base class provides:
    # - Common fields (`name`, `public_service`, `has_backups`, `additional_components`)
    # - Registry of all known service types via {.service_types}
    # - Address delegation to the parent guest
    # - Default no-op implementations of backup, restore, and SSL certificate hooks
    class Base
      include Mongoid::Document
      include Mongoid::Timestamps
      include CloudModel::Mixins::BackupTools
      include CloudModel::Mixins::HasIssues

      # @!attribute [rw] name
      #   @return [String, nil] optional human-readable label for this service instance
      field :name, type: String

      # @!attribute [rw] public_service
      #   @return [Boolean] when true, {#external_address} returns the guest's public IP
      field :public_service, type: Mongoid::Boolean, default: false

      # @!attribute [rw] has_backups
      #   @return [Boolean] whether backup scheduling is enabled for this service;
      #     forced to `false` unless {#backupable?} returns `true`
      field :has_backups, type: Mongoid::Boolean, default: false

      # @!attribute [rw] additional_components
      #   @return [Array<String>] extra component symbols to install alongside the
      #     service's own required components (stored as strings, returned as symbols
      #     by {#components_needed})
      field :additional_components, type: Array, default: []

      embedded_in :guest, class_name: "CloudModel::Guest", inverse_of: :services

      # @return [Hash{Symbol => Class}] map of service type keys to their model classes
      def self.service_types
        {
          ssh: CloudModel::Services::Ssh,
          nginx: CloudModel::Services::Nginx,
          phpfpm: CloudModel::Services::Phpfpm,
          mongodb: CloudModel::Services::Mongodb,
          redis: CloudModel::Services::Redis,
          mariadb: CloudModel::Services::Mariadb,
          neo4j: CloudModel::Services::Neo4j,
          fuseki: CloudModel::Services::Fuseki,
          solr: CloudModel::Services::Solr,
          tomcat: CloudModel::Services::Tomcat,
          collabora: CloudModel::Services::Collabora,
          jitsi: CloudModel::Services::Jitsi,
          forgejo: CloudModel::Services::Forgejo,
          rake: CloudModel::Services::Rake,
          backup: CloudModel::Services::Backup,
          monitoring: CloudModel::Services::Monitoring,
        }
      end

      # @return [Symbol, nil] the key from {.service_types} matching this instance's class
      def service_type
        self.class.service_types.each do |type, model_class|
          if self.class == model_class
            return type
          end
        end
        nil
      end

      # Finds a service by its embedded document ID across all guests.
      #
      # @param id [String, BSON::ObjectId] the service `_id`
      # @return [Base] the matching service instance
      def self.find(id)
        CloudModel::Guest.find_by("services._id" => id).services.find(id)
      end

      # @return [CloudModel::Host] the host running this service's guest
      def host
        guest.host
      end

      # @return [String] the guest's private IP address
      def private_address
        guest.private_address
      end

      # @return [String, nil] the guest's external IP when {#public_service} is true, else `nil`
      def external_address
        if public_service
          guest.external_address
        end
      end

      # @return [Array] issue chain for monitoring: `[host, guest, self]`
      def item_issue_chain
        [host, guest, self]
      end

      # @return [Array<Array>] list of `[port, protocol]` pairs this service uses;
      #   default is `[[port, :tcp]]` — override for multi-port or UDP services
      def used_ports
        [[port, :tcp]]
      end

      # @return [Symbol] service kind used by the worker to choose the deploy strategy
      def kind
        :unknown
      end

      # @return [Array<Symbol>] component symbols required by this service, including
      #   any symbols from {#additional_components}
      def components_needed
        additional_components.map &:to_sym
      end

      # @return [Hash, false] monitoring data hash, or `false` if no health check is available
      def service_status
        false
      end

      # Hook called after deployment to install SSL certificates.
      # Default no-op; override in subclasses that support TLS.
      def update_crt(options = {})
        # No ssl certs used by default, do nothing
      end

      # @return [Boolean] whether this service supports backup scheduling (default: `false`)
      def backupable?
        false
      end

      # Setter that prevents enabling backups when {#backupable?} is false.
      # @param state [Boolean]
      def has_backups=(state)
        state = false unless backupable?
        self[:has_backups] = state
      end

      # @return [String] filesystem path where backups for this service are stored
      def backup_directory
        "#{CloudModel.config.backup_directory}/#{guest.host.id}/#{guest.id}/services/#{id}"
      end

      # Perform a backup. Raises unless overridden by a backupable subclass.
      def backup
        raise "Service has no backups"
      end

      # Restore from a backup. Raises unless overridden by a backupable subclass.
      # @param timestamp [String] backup label to restore (default: `"latest"`)
      def restore timestamp='latest'
        raise "Service has no restore"
      end
    end
  end
end
