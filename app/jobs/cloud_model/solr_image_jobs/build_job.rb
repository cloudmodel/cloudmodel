module CloudModel
  module SolrImageJobs
    class BuildJob < CloudModel::BaseJob
      def perform(solr_image_id)
        solr_image_worker = CloudModel::Workers::SolrImageWorker.new CloudModel::SolrImage.find(solr_image_id)

        solr_image_worker.build debug: true
      end
    end
  end
end