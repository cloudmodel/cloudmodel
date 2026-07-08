module CloudModel
  module HostJobs
    class DeployJob < CloudModel::BaseJob
      def perform(host_id)
        host = CloudModel::Host.find(host_id)
        host.with_live_log verbose: true do
          CloudModel::Workers::HostWorker.new(host).deploy
        end
      end
    end
  end
end