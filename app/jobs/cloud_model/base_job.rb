module CloudModel
  class BaseJob < ActiveJob::Base
    queue_as CloudModel.config.job_queue

    # Most jobs are safe to ignore if the underlying records are no longer available
    discard_on ActiveJob::DeserializationError

    # Runs the block with $stdout teed into the subject's live console
    # (Mixins::LiveLog) — the one shared mechanism behind every deploy/build
    # console in the admin UI.
    def with_live_log subject
      subject.restart_live_log
      CloudModel::StdoutTee.capture ->(text) { subject.append_live_log text } do
        yield
      end
    ensure
      subject.flush_live_log
    end

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
