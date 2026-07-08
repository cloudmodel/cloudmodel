module CloudModel
  module HostTemplateJobs
    class BuildJob < CloudModel::BaseJob
      def perform(template_id, host_id)
        host = CloudModel::Host.find(host_id)
        template = CloudModel::HostTemplate.find(template_id)
        template.with_live_log verbose: true do
          CloudModel::Workers::HostTemplateWorker.new(host).build_template template, debug: true
        end
      end
    end
  end
end