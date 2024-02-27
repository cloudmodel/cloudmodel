module CloudModel
  module HostTemplateJobs
    class BuildJob < CloudModel::BaseJob
      def perform(host_id, template_id)
        host = CloudModel::Host.find(host_id)
        template = CloudModel::HostTemplate.find(template_id)
        host_template_worker = CloudModel::Workers::HostTemplateWorker.new host

        host_template_worker.build_template @template, debug: true
      end
    end
  end
end