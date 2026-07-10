# encoding: UTF-8

require 'spec_helper'

# Tested through GuestTemplate, which includes the mixin
describe CloudModel::Mixins::HasZfsBuildVolume do
  let(:template_type) { Factory :guest_template_type }
  subject { Factory :guest_template, template_type: template_type, build_state: :finished }

  let(:host) { Factory :host, name: 'deploy-host' }
  let(:volume) { double CloudModel::BuildZfsVolume }

  it { expect(subject.class).to include CloudModel::Mixins::HasZfsBuildVolume }
  it { expect(subject).to belong_to(:build_host).of_type(CloudModel::Host).with_optional }

  describe 'build_volume' do
    it 'should return the BuildZfsVolume on the given host' do
      volume = subject.build_volume host

      expect(volume).to be_a CloudModel::BuildZfsVolume
      expect(volume.host).to eq host
      expect(volume.dataset_name).to eq subject.build_dataset
      expect(volume.mountpoint).to eq subject.build_mountpoint
    end
  end

  describe 'claim_build!' do
    it 'should claim a finished template and set it pending' do
      expect(subject.claim_build!).to eq true
      expect(subject.build_state).to eq :pending
      expect(subject.reload.build_state).to eq :pending
    end

    it 'should claim a failed template' do
      subject.update_attributes build_state: :failed

      expect(subject.claim_build!).to eq true
    end

    it 'should not claim a template already being built' do
      subject.update_attributes build_state: :running

      expect(subject.claim_build!).to eq false
    end

    it 'should let exactly one of two concurrent claimers win' do
      other_handle = CloudModel::GuestTemplate.find subject.id

      expect(subject.claim_build!).to eq true
      expect(other_handle.claim_build!).to eq false
    end
  end

  describe 'ensure_build_volume!' do
    before do
      allow(subject).to receive(:build_volume).with(host).and_return(volume)
      allow(subject).to receive(:sleep)
    end

    it 'should do nothing when the volume is already ready' do
      allow(volume).to receive(:ready?).and_return(true)
      expect(subject).not_to receive(:sync_build_volume_to)
      expect(subject).not_to receive(:build_on!)

      expect(subject.ensure_build_volume!(host)).to eq volume
    end

    it 'should sync the volume over when another host has it' do
      allow(volume).to receive(:ready?).and_return(false, true)
      expect(subject).to receive(:sync_build_volume_to).with(host).and_return(true)
      expect(subject).not_to receive(:build_on!)

      expect(subject.ensure_build_volume!(host)).to eq volume
    end

    it 'should claim and build on the target host when no build host is configured' do
      allow(CloudModel::Host).to receive(:build_host).and_return(nil)
      allow(volume).to receive(:ready?).and_return(false, true)
      allow(subject).to receive(:sync_build_volume_to).and_return(false)
      expect(subject).to receive(:build_on!).with(host)

      subject.ensure_build_volume! host
      expect(subject.build_state).to eq :pending
    end

    it 'should build on the configured build host' do
      build_host = Factory :host, name: 'build-host'
      allow(CloudModel::Host).to receive(:build_host).and_return(build_host)
      allow(volume).to receive(:ready?).and_return(false, true)
      allow(subject).to receive(:sync_build_volume_to).and_return(false)
      expect(subject).to receive(:build_on!).with(build_host)

      subject.ensure_build_volume! host
    end

    it 'should wait for a concurrent build instead of building twice' do
      subject.update_attributes build_state: :running
      allow(volume).to receive(:ready?).and_return(false, true)
      expect(subject).not_to receive(:build_on!)
      # While another process builds, don't scan hosts — just wait
      expect(subject).not_to receive(:sync_build_volume_to)
      expect(subject).to receive(:sleep).with(30)

      subject.ensure_build_volume! host
    end

    it 'should raise when a concurrent build does not finish in time' do
      subject.update_attributes build_state: :running
      allow(volume).to receive(:ready?).and_return(false)
      allow(subject).to receive(:sync_build_volume_to).and_return(false)
      allow(Time).to receive(:now).and_return(Time.new(2026, 7, 9, 12, 0), Time.new(2026, 7, 9, 15, 0))

      expect { subject.ensure_build_volume! host }.to raise_error(/Timeout waiting for concurrent build/)
    end
  end

  describe 'sync_build_volume_to' do
    let(:source_host) { Factory :host, name: 'build-host' }

    before do
      allow(CloudModel.config).to receive(:skip_sync_images).and_return(false)
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(source_host).to receive(:ssh_address).and_return('10.0.0.1')
      allow(host).to receive(:ssh_address).and_return('10.0.0.2')
    end

    it 'should skip when skip_sync_images is configured' do
      allow(CloudModel.config).to receive(:skip_sync_images).and_return(true)

      expect(subject.sync_build_volume_to(host)).to eq false
    end

    it 'should return false when no host has the volume' do
      allow(subject).to receive(:build_volume_source_host).and_return(nil)

      expect(subject.sync_build_volume_to(host)).to eq false
    end

    it 'should pipe compressed zfs send through the admin machine to the target host' do
      allow(subject).to receive(:build_volume_source_host).with(exclude: host).and_return(source_host)

      expect(subject).to receive(:local_exec!).with(
        "ssh -C -i /data/keys/id_rsa root@10.0.0.2 'zfs list #{File.dirname(subject.build_dataset)} >/dev/null 2>&1 || zfs create -p #{File.dirname(subject.build_dataset)}'",
        /Failed to create parent dataset/
      )
      expect(subject).to receive(:local_exec!).with(
        "ssh -C -i /data/keys/id_rsa root@10.0.0.1 'zfs send -p #{subject.build_snapshot}' | ssh -C -i /data/keys/id_rsa root@10.0.0.2 'zfs receive -u -F #{subject.build_dataset}'",
        /Failed to sync build volume/
      )

      expect(subject.sync_build_volume_to(host)).to eq true
    end

    it 'should log and return false when the sync fails' do
      allow(subject).to receive(:build_volume_source_host).and_return(source_host)
      allow(subject).to receive(:local_exec!).and_raise('broken pipe')
      expect(CloudModel).to receive(:log_exception)

      expect(subject.sync_build_volume_to(host)).to eq false
    end
  end

  describe 'build_volume_source_host' do
    it 'should prefer the recorded build host' do
      build_host = Factory :host, name: 'build-host'
      subject.update_attributes build_host: build_host
      ready_volume = double CloudModel::BuildZfsVolume, ready?: true
      allow(subject).to receive(:build_volume).with(build_host).and_return(ready_volume)

      expect(subject.build_volume_source_host).to eq build_host
    end

    it 'should exclude the given host and skip hosts without the volume' do
      other = Factory :host, name: 'other-host'
      allow(CloudModel::Host).to receive(:build_host).and_return(nil)
      allow(CloudModel::Host).to receive(:all).and_return([host, other])
      allow(subject).to receive(:build_volume).with(other).and_return(double(ready?: false))

      expect(subject.build_volume_source_host(exclude: host)).to be_nil
    end

    it 'should tolerate unreachable hosts' do
      other = Factory :host, name: 'other-host'
      allow(CloudModel::Host).to receive(:build_host).and_return(nil)
      allow(CloudModel::Host).to receive(:all).and_return([other])
      allow(subject).to receive(:build_volume).with(other).and_raise(Errno::EHOSTUNREACH)
      allow(CloudModel).to receive(:log_exception)

      expect(subject.build_volume_source_host).to be_nil
    end
  end
end
