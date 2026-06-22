require 'spec_helper'

describe CloudModel::GuestCoreTemplateJobs::BuildJob do
  let(:host) { double CloudModel::Host }
  let(:template) { double CloudModel::GuestCoreTemplate }
  let(:worker) { double CloudModel::Workers::GuestTemplateWorker }

  it 'finds host and template, then builds the core template in debug mode' do
    expect(CloudModel::Host).to receive(:find).with('host-id').and_return(host)
    expect(CloudModel::GuestCoreTemplate).to receive(:find).with('template-id').and_return(template)
    expect(CloudModel::Workers::GuestTemplateWorker).to receive(:new).with(host).and_return(worker)
    expect(worker).to receive(:build_core_template).with(template, debug: true)

    subject.perform('template-id', 'host-id')
  end
end
