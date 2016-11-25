module CloudModel
  module Components
    class SolrWorker < BaseWorker
      def build build_path   
        chroot! build_path, "apt-get install lsof -y", "Failed to install lsof"
        chroot! build_path, "useradd solr -d /var/solr -r -c 'Solr User'", "Failed to add user shinken"
      end
    end
  end
end