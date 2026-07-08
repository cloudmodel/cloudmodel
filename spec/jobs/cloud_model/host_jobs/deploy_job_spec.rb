require 'spec_helper'

describe CloudModel::HostJobs::DeployJob do
  let(:host) { double CloudModel::Host }
  let(:worker) { double CloudModel::Workers::HostWorker }

  it 'finds the host, builds a HostWorker and deploys' do
    expect(CloudModel::Host).to receive(:find).with('host-id').and_return(host)
    allow(host).to receive(:with_live_log).and_yield
    expect(CloudModel::Workers::HostWorker).to receive(:new).with(host).and_return(worker)
    expect(worker).to receive(:deploy)

    subject.perform('host-id')
  end
end
