require 'spec_helper'

describe CloudModel::GuestJobs::RedeployJob do
  let(:guest) { double CloudModel::Guest }
  let(:worker) { double CloudModel::Workers::GuestWorker }

  it 'finds the guest, builds a GuestWorker and redeploys' do
    expect(CloudModel::Guest).to receive(:find).with('guest-id').and_return(guest)
    expect(CloudModel::Workers::GuestWorker).to receive(:new).with(guest).and_return(worker)
    expect(worker).to receive(:redeploy)

    subject.perform('guest-id')
  end
end
