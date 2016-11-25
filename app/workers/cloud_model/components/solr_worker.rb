module CloudModel
  module Components
    class SolrWorker < BaseWorker
      def build build_path     
        render_to_remote "/cloud_model/guest/etc/systemd/system/solr.service", "#{build_path}/etc/systemd/system/solr.service"     
      end
    end
  end
end