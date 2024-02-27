module CloudModel
  module Services
    module WebImageJobs
      class RedeployJob < CloudModel::BaseJob
        def perform(service_id, guest_id)
          raise "No GUEST_ID given" unless guest_id
          raise "No SERVICE_ID given" unless service_id
          guest = CloudModel::Guest.find guest_id
          nginx_service = @guest.services.find service_id
          raise "Not an nginx service with webimage" unless nginx_service._type == "CloudModel::Services::Nginx" and nginx_service.web_image_id

          nginx_worker = CloudModel::Workers::Services::NginxWorker.new nginx_service
          nginx_worker.redeploy
        end
      end
    end
  end
end