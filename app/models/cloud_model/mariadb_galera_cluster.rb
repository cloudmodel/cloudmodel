module CloudModel
  # Represents a MariaDB Galera multi-master replication cluster.
  #
  # Services of type {Services::Mariadb} reference a cluster by setting
  # `mariadb_galera_cluster_id`. The cluster model aggregates those services
  # and exposes helper methods for generating Galera configuration strings.
  class MariadbGaleraCluster
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] name
    #   @return [String] cluster name (used in Galera config as `wsrep_cluster_name`)
    field :name, type: String

    # Returns all MariaDB service instances that are members of this cluster.
    # @return [Array<CloudModel::Services::Mariadb>]
    def services
      CloudModel::Guest.where("services.mariadb_galera_cluster_id" => id).map{ |guest|
        guest.services.where(mariadb_galera_cluster_id: id).to_a
      }.flatten
    end

    # Adds a MariaDB service to this cluster by setting its `mariadb_galera_cluster_id`.
    # @param service [CloudModel::Services::Mariadb]
    # @return [CloudModel::Services::Mariadb]
    def add_service service
      service.update_attribute :mariadb_galera_cluster_id, id
    end

    # Returns an array of `{ 'ip' => ..., 'port' => ... }` hashes for all member services.
    # @return [Array<Hash>]
    def cluster_hosts
      services.map do |s|
        {'ip' => s.private_address, 'port' => s.mariadb_galera_port}
      end
    end

    # Returns the Galera `wsrep_cluster_address` value, e.g. `"10.0.0.1:4567,10.0.0.2:4567"`.
    # @return [String]
    def cluster_hosts_string
      cluster_hosts.map{|h| "#{h['ip']}:#{h['port']}"} * ','
    end
  end
end