module CloudModel
  module Services
    class Base
      include Mongoid::Document
      include Mongoid::Timestamps
      include CloudModel::Mixins::BackupTools
      include CloudModel::Mixins::HasIssues

      field :name, type: String
      field :public_service, type: Mongoid::Boolean, default: false
      field :has_backups, type: Mongoid::Boolean, default: false
      field :additional_components, type: Array, default: []

      embedded_in :guest, class_name: "CloudModel::Guest", inverse_of: :services

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
          rake: CloudModel::Services::Rake,
          backup: CloudModel::Services::Backup,
          monitoring: CloudModel::Services::Monitoring,
        }
      end

      def service_type
        self.class.service_types.each do |type, model_class|
          if self.class == model_class
            return type
          end
        end
        nil
      end

      def self.find(id)
        CloudModel::Guest.find_by("services._id" => id).services.find(id)
      end

      def host
        guest.host
      end

      def private_address
        guest.private_address
      end

      def external_address
        if public_service
          guest.external_address
        end
      end

      def item_issue_chain
        [host, guest, self]
      end

      def used_ports
        [port]
      end

      def kind
        :unknown
      end

      def components_needed
        additional_components.map &:to_sym
      end

      def service_status
        false
      end

      def update_crt(options = {})
        # No ssl certs used by default, do nothing
      end

      def backupable?
        false
      end

      def has_backups=(state)
        state = false unless backupable?
        self[:has_backups] = state
      end

      def backup_directory
        "#{CloudModel.config.backup_directory}/#{guest.host.id}/#{guest.id}/services/#{id}"
      end

      def backup
        raise "Service has no backups"
      end

      def restore timestamp='latest'
        raise "Service has no restore"
      end
    end
  end
end
