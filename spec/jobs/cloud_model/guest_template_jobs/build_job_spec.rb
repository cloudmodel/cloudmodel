require 'spec_helper'

describe CloudModel::GuestTemplateJobs::BuildJob do
  let(:host) { double CloudModel::Host }
  let(:template) { double CloudModel::GuestTemplate }
  let(:worker) { double CloudModel::Workers::GuestTemplateWorker }

  it 'finds host and template, then builds the template in debug mode' do
    expect(CloudModel::Host).to receive(:find).with('host-id').and_return(host)
    expect(CloudModel::GuestTemplate).to receive(:find).with('template-id').and_return(template)
    expect(CloudModel::Workers::GuestTemplateWorker).to receive(:new).with(host).and_return(worker)
    expect(worker).to receive(:build_template).with(template, debug: true)

    subject.perform('template-id', 'host-id')
  end
end
