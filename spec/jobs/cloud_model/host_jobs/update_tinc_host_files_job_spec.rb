require 'spec_helper'

describe CloudModel::HostJobs::UpdateTincHostFilesJob do
  let(:host1) { double CloudModel::Host, name: 'core1' }
  let(:host2) { double CloudModel::Host, name: 'core2' }
  let(:worker1) { double CloudModel::Workers::HostWorker }
  let(:worker2) { double CloudModel::Workers::HostWorker }

  before do
    allow(CloudModel::Host).to receive(:tinc_peers_of).with(nil).and_return [host1, host2]
    allow(CloudModel::Workers::HostWorker).to receive(:new).with(host1).and_return worker1
    allow(CloudModel::Workers::HostWorker).to receive(:new).with(host2).and_return worker2
  end

  it 'updates the tinc host files on every deployed host' do
    expect(worker1).to receive(:update_tinc_host_files).and_return ['old_vm']
    expect(worker2).to receive(:update_tinc_host_files).and_return []

    subject.perform
  end

  it 'continues with the other hosts when one fails and then reports the failure' do
    expect(worker1).to receive(:update_tinc_host_files).and_raise 'ssh down'
    expect(worker2).to receive(:update_tinc_host_files).and_return []
    allow(CloudModel).to receive(:log_exception)

    expect { subject.perform }.to raise_error(/core1/)
  end
end
