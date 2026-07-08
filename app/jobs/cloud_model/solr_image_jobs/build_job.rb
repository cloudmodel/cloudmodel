module CloudModel
  module SolrImageJobs
    class BuildJob < CloudModel::BaseJob
      def perform(solr_image_id)
        solr_image = CloudModel::SolrImage.find(solr_image_id)
        with_live_log solr_image do
          CloudModel::Workers::SolrImageWorker.new(solr_image).build debug: true
        end
      end
    end
  end
end