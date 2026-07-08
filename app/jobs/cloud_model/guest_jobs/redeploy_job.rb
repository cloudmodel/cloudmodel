module CloudModel
  module GuestJobs
    class RedeployJob < CloudModel::BaseJob
      def perform(guest_id)
        guest = CloudModel::Guest.find(guest_id)
        with_live_log guest do
          CloudModel::Workers::GuestWorker.new(guest).redeploy
        end
      end
    end
  end
end