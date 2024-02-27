module CloudModel
  module WebImageJobs
    class RedeployJob < CloudModel::BaseJob
      def perform(web_image_id)
        web_image_worker = CloudModel::Workers::WebImageWorker.new CloudModel::WebImage.find(web_image_id)
        web_image_worker.redeploy
      end
    end
  end
end