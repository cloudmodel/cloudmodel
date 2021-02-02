module CloudModel
  class MariadbGaleraCluster
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    field :name, type: String

    def services
      CloudModel::Guest.where("services.mariadb_galera_cluster_id" => id).map{ |guest|
        guest.services.where(mariadb_galera_cluster_id: id).to_a
      }.flatten
    end

    def add_service service
      service.update_attribute :mariadb_galera_cluster_id, id
    end

    def cluster_hosts
      services.map do |s|
        {'ip' => s.private_address, 'port' => s.mariadb_galera_port}
      end
    end

    def cluster_hosts_string
      cluster_hosts.map{|h| "#{h['ip']}:#{h['port']}"} * ','
    end
  end
end