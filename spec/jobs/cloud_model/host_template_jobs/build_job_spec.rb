require 'spec_helper'

describe CloudModel::HostTemplateJobs::BuildJob do
  let(:host) { double CloudModel::Host }
  let(:template) { double CloudModel::HostTemplate }
  let(:worker) { double CloudModel::Workers::HostTemplateWorker }

  it 'finds host and template, then builds the host template in debug mode' do
    expect(CloudModel::Host).to receive(:find).with('host-id').and_return(host)
    expect(CloudModel::HostTemplate).to receive(:find).with('template-id').and_return(template)
    expect(CloudModel::Workers::HostTemplateWorker).to receive(:new).with(host).and_return(worker)
    expect(worker).to receive(:build_template).with(template, debug: true)

    subject.perform('template-id', 'host-id')
  end
end
