module CloudModel
  module GuestJobs
    class DeployJob < CloudModel::BaseJob
      def perform(guest_id)
        guest = CloudModel::Guest.find(guest_id)
        with_live_log guest do
          CloudModel::Workers::GuestWorker.new(guest).deploy
        end
      end
    end
  end
end