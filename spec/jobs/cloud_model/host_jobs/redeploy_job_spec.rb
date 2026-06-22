require 'spec_helper'

describe CloudModel::HostJobs::RedeployJob do
  let(:host) { double CloudModel::Host }
  let(:worker) { double CloudModel::Workers::HostWorker }

  it 'finds the host, builds a HostWorker and redeploys' do
    expect(CloudModel::Host).to receive(:find).with('host-id').and_return(host)
    expect(CloudModel::Workers::HostWorker).to receive(:new).with(host).and_return(worker)
    expect(worker).to receive(:redeploy)

    subject.perform('host-id')
  end
end
