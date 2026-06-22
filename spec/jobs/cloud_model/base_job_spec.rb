require 'spec_helper'

describe CloudModel::BaseJob do
  it 'sets queue_as to the configured job_queue (:default)' do
    expect(described_class.queue_name).to eq 'default'
  end

  it 'discards on ActiveJob::DeserializationError' do
    # The discard handler is registered as a rescue callback.
    rescue_handlers = described_class.rescue_handlers.map(&:first)
    expect(rescue_handlers).to include('ActiveJob::DeserializationError')
  end

  describe '.human_name' do
    it 'builds a human name from the namespaced class name' do
      expect(CloudModel::GuestJobs::DeployJob.human_name).to eq 'Deploy Guest'
    end

    it 'strips the Job and Jobs suffixes' do
      expect(CloudModel::HostTemplateJobs::BuildJob.human_name).to eq 'Build HostTemplate'
    end
  end
end
