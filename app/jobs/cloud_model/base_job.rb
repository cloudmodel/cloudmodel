module CloudModel
  class BaseJob < ActiveJob::Base
    queue_as CloudModel.config.job_queue

    # Most jobs are safe to ignore if the underlying records are no longer available
    discard_on ActiveJob::DeserializationError

    # def provider_job
    #   Delayed::Job.find provider_job_id
    # end

    # "CloudModel::WebImageJobs::RedeployJob" => "Redeploy WebImage".
    # Must not assume three name segments — jobs like
    # Cloud::WebImageRebuildAndRedeployJob have only two (this crashed the
    # dashboard job list with nil.gsub).
    def self.human_name
      parts = name.split('::')
      action = (parts.pop || '').gsub(/Job$/, '')
      subject = (parts.pop || '').gsub(/Jobs$/, '')
      subject = '' if %w(Cloud CloudModel).include? subject
      [action, subject].reject(&:empty?) * ' '
    end
  end
end
