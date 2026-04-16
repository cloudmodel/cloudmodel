module CloudModel
  module Workers
    module Components
      # Component worker that prepares a guest template to run Apache Solr.
      #
      # Installs `lsof` (used by the Solr start script for port checking) and
      # creates a dedicated `solr` system user with home `/var/solr`.
      # The Solr binary itself is deployed at runtime by {SolrWorker}.
      class SolrComponentWorker < BaseComponentWorker
        def build build_path   
          chroot! build_path, "apt-get install lsof -y", "Failed to install lsof"
          chroot! build_path, "useradd solr -d /var/solr -r -c 'Solr User'", "Failed to add user solr"
        end
      end
    end
  end
end