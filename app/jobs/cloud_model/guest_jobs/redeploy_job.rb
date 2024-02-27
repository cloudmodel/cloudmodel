module CloudModel
  module GuestJobs
    class RedeployJob < CloudModel::BaseJob
      def perform(guest_id)
        guest_worker = CloudModel::Workers::GuestWorker.new CloudModel::Guest.find(guest_id)
        guest_worker.redeploy
      end
    end
  end
end