module CloudModel
  module HostJobs
    class RedeployJob < CloudModel::BaseJob
      def perform(host_id)
        host = CloudModel::Host.find(host_id)
        with_live_log host do
          CloudModel::Workers::HostWorker.new(host).redeploy
        end
      end
    end
  end
end