require 'spec_helper'

describe CloudModel::GuestJobs::SyncAuthorizedKeysJob do
  let(:group_a) { BSON::ObjectId.new }
  let(:group_b) { BSON::ObjectId.new }

  def nginx_with groups
    service = CloudModel::Services::Nginx.new
    allow(service).to receive(:capistrano_ssh_group_ids).and_return groups
    service
  end

  let(:service_a) { nginx_with [group_a] }
  let(:service_b) { nginx_with [group_b] }
  let(:guest_a) { double CloudModel::Guest, name: 'graph-a', up_state: :started, services: [service_a] }
  let(:guest_b) { double CloudModel::Guest, name: 'graph-b', up_state: :started, services: [service_b] }
  let(:stopped) { double CloudModel::Guest, name: 'old', up_state: :stopped, services: [nginx_with([group_a])] }

  before { allow(CloudModel::Guest).to receive(:all).and_return [guest_a, guest_b, stopped] }

  describe '.services_for' do
    it 'returns running guests whose nginx uses one of the groups' do
      expect(described_class.services_for([group_a.to_s])).to eq [[guest_a, service_a]]
    end

    it 'returns all running guests with groups when no group is given' do
      expect(described_class.services_for).to eq [[guest_a, service_a], [guest_b, service_b]]
    end
  end

  it 'syncs the affected services' do
    worker = double sync_authorized_keys: {state: :applied, added: [], removed: ['former@vm']}
    allow(service_a).to receive(:worker).and_return worker
    expect(worker).to receive(:sync_authorized_keys)
    expect(service_b).not_to receive(:worker)

    subject.perform([group_a.to_s])
  end

  it 'goes on after a failure and reports it' do
    allow(service_a).to receive(:worker).and_raise 'container gone'
    worker_b = double sync_authorized_keys: {state: :unchanged, added: [], removed: []}
    allow(service_b).to receive(:worker).and_return worker_b
    allow(CloudModel).to receive(:log_exception)
    expect(worker_b).to receive(:sync_authorized_keys)

    expect { subject.perform }.to raise_error(/graph-a/)
  end
end
