module CloudModel
  module GuestJobs
    class RedeployJob < CloudModel::BaseJob
      def perform(guest_id)
        guest = CloudModel::Guest.find(guest_id)
        guest.with_live_log verbose: true do
          CloudModel::Workers::GuestWorker.new(guest).redeploy
        end
      end
    end
  end
end