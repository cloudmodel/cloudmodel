module CloudModel
  class BaseJob < ActiveJob::Base
    queue_as CloudModel.config.job_queue

    # Most jobs are safe to ignore if the underlying records are no longer available
    discard_on ActiveJob::DeserializationError

    # def provider_job
    #   Delayed::Job.find provider_job_id
    # end

    def self.human_name
      ns, subject, action = name.split('::')
      "#{action.gsub(/Job$/, '')} #{subject.gsub(/Jobs$/, '')}"
    end
  end
end
