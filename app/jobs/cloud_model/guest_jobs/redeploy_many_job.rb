module CloudModel
  module GuestJobs
    class RedeployManyJob < CloudModel::BaseJob
      def perform(guest_ids)
        CloudModel::Guest.redeploy_batch! guest_ids
      end
    end
  end
end
