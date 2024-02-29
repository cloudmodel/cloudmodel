module CloudModel
  module GuestTemplateJobs
    class BuildJob < CloudModel::BaseJob
      def perform(template_id, host_id)
        host = CloudModel::Host.find(host_id)
        template = CloudModel::GuestTemplate.find(template_id)
        guest_template_worker = CloudModel::Workers::GuestTemplateWorker.new host

        guest_template_worker.build_template template, debug: true
      end
    end
  end
end