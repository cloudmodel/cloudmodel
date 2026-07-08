module CloudModel
  module HostJobs
    class RedeployJob < CloudModel::BaseJob
      def perform(host_id)
        host = CloudModel::Host.find(host_id)
        host.with_live_log verbose: true do
          CloudModel::Workers::HostWorker.new(host).redeploy
        end
      end
    end
  end
end