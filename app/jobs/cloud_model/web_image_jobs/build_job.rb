module CloudModel
  module WebImageJobs
    class BuildJob < CloudModel::BaseJob
      def perform(web_image_id)
        web_image_worker = CloudModel::Workers::WebImageWorker.new CloudModel::WebImage.find(web_image_id)
        web_image_worker.build
      end
    end
  end
end