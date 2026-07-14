module CloudModel
  module WebImageJobs
    class RedeployJob < CloudModel::BaseJob
      def perform(web_image_id)
        # Redeploy rolls the already-built artifact out per service (each on its
        # own guest/host); the worker needs no build host of its own.
        web_image_worker = CloudModel::Workers::WebImageWorker.new nil, CloudModel::WebImage.find(web_image_id)
        web_image_worker.redeploy verbose: true
      end
    end
  end
end