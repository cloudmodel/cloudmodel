module CloudModel
  module GuestJobs
    class DeployJob < CloudModel::BaseJob
      def perform(guest_id)
        guest_worker = CloudModel::Workers::GuestWorker.new CloudModel::Guest.find(guest_id)
        guest_worker.deploy
      end
    end
  end
end