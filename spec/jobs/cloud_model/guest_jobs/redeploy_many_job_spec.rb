require 'spec_helper'

describe CloudModel::GuestJobs::RedeployManyJob do
  let(:guest_a) { double CloudModel::Guest, deploy_state: :pending, host_id: 'host-1', name: 'guest-a' }
  let(:guest_b) { double CloudModel::Guest, deploy_state: :pending, host_id: 'host-1', name: 'guest-b' }
  let(:guest_other_host) { double CloudModel::Guest, deploy_state: :pending, host_id: 'host-2', name: 'guest-c' }
  let(:guest_not_pending) { double CloudModel::Guest, deploy_state: :running, host_id: 'host-1', name: 'guest-d' }

  let(:criteria) { double 'Criteria' }

  before do
    allow(subject).to receive(:puts)
  end

  it 'redeploys all pending guests grouped by host' do
    expect(CloudModel::Guest).to receive(:where).with(:id.in => %w[a b c]).and_return(criteria)
    allow(criteria).to receive(:to_a).and_return([guest_a, guest_b, guest_other_host])

    worker_a = double CloudModel::Workers::GuestWorker
    worker_b = double CloudModel::Workers::GuestWorker
    worker_c = double CloudModel::Workers::GuestWorker

    expect(CloudModel::Workers::GuestWorker).to receive(:new).with(guest_a).and_return(worker_a)
    expect(CloudModel::Workers::GuestWorker).to receive(:new).with(guest_b).and_return(worker_b)
    expect(CloudModel::Workers::GuestWorker).to receive(:new).with(guest_other_host).and_return(worker_c)
    expect(worker_a).to receive(:redeploy)
    expect(worker_b).to receive(:redeploy)
    expect(worker_c).to receive(:redeploy)

    subject.perform(%w[a b c])
  end

  it 'skips guests that are not in pending deploy_state' do
    expect(CloudModel::Guest).to receive(:where).with(:id.in => %w[a d]).and_return(criteria)
    allow(criteria).to receive(:to_a).and_return([guest_a, guest_not_pending])

    worker_a = double CloudModel::Workers::GuestWorker
    expect(CloudModel::Workers::GuestWorker).to receive(:new).with(guest_a).and_return(worker_a)
    expect(worker_a).to receive(:redeploy)
    expect(CloudModel::Workers::GuestWorker).not_to receive(:new).with(guest_not_pending)

    subject.perform(%w[a d])
  end
end
