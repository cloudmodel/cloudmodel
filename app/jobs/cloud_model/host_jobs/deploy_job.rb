module CloudModel
  module HostJobs
    class DeployJob < CloudModel::BaseJob
      def perform(host_id)
        host_worker = CloudModel::Workers::HostWorker.new CloudModel::Host.find(host_id)
        host_worker.deploy
      end
    end
  end
end