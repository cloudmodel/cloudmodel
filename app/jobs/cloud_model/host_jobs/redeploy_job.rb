module CloudModel
  module HostJobs
    class RedeployJob < CloudModel::BaseJob
      def perform(host_id)
        host_worker = CloudModel::Workers::HostWorker.new CloudModel::Host.find(host_id)
        host_worker.redeploy
      end
    end
  end
end