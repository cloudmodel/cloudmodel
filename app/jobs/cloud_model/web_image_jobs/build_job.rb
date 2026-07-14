module CloudModel
  module WebImageJobs
    class BuildJob < CloudModel::BaseJob
      def perform(web_image_id)
        # build! fans out to a per-arch build host for each (template, arch)
        # the image is consumed by; each build streams into the web image's
        # own console (WebImageWorker#with_build_log).
        CloudModel::WebImage.find(web_image_id).build! force: true
      end
    end
  end
end