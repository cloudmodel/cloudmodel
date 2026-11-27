# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::FleetComponentWorker do
  let(:template) { double 'template', arch: 'amd64' }
  let(:host) { double CloudModel::Host }
  subject { CloudModel::Workers::Components::FleetComponentWorker.new template, host }

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  it 'should default to the pinned release' do
    expect(subject.version).to eq '4.96.0'
  end

  it 'should install the release pinned on the component' do
    worker = CloudModel::Workers::Components::FleetComponentWorker.new template, host, component: CloudModel::Components::FleetComponent.new(version: '4.97.0')
    expect(worker.version).to eq '4.97.0'
  end

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
      allow(subject).to receive :mkdir_p
      allow(subject).to receive :render_to_remote
    end

    it 'should refuse architectures Fleet publishes no server for' do
      allow(template).to receive(:arch).and_return 'arm64'
      expect(subject).not_to receive(:chroot!)
      expect { subject.build '/tmp/build' }.to raise_error(RuntimeError, /amd64 only, not for arm64/)
    end

    it 'should create the fleet system user and its directories' do
      expect(subject).to receive(:chroot!).with('/tmp/build', /adduser --system --home \/var\/lib\/fleet .* fleet$/, 'Failed to create fleet user')
      expect(subject).to receive(:chroot!).with('/tmp/build', /mkdir -p \/etc\/fleet \/var\/lib\/fleet \/var\/log\/fleet/, 'Failed to create fleet directories')
      subject.build '/tmp/build'
    end

    it 'should download server, CLI and the checksums of the release' do
      expect(subject).to receive(:chroot!).with('/tmp/build', %r{releases/download/fleet-v4\.96\.0/checksums\.txt .*fleet_v4\.96\.0_linux\.tar\.gz .*fleetctl_v4\.96\.0_linux_amd64\.tar\.gz}, 'Failed to download fleet 4.96.0 (amd64)')
      subject.build '/tmp/build'
    end

    it 'should check both tarballs against checksums.txt before installing' do
      expect(subject).to receive(:chroot!).with('/tmp/build', /grep -E .*fleet_v4\\\\\.96\\\\\.0_linux\\\\\.tar.* checksums\.txt \| sha256sum -c --strict -/, /Checksum of fleet_v4\.96\.0_linux\.tar\.gz/).ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', /fleetctl_v4\\\\\.96\\\\\.0_linux_amd64.* sha256sum -c --strict -/, /Checksum of fleetctl_v4\.96\.0_linux_amd64\.tar\.gz/).ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', /install -m 755 fleet_v4\.96\.0_linux\/fleet \/usr\/bin\/fleet && install -m 755 fleetctl_v4\.96\.0_linux_amd64\/fleetctl \/usr\/bin\/fleetctl/, 'Failed to install fleet binaries').ordered
      subject.build '/tmp/build'
    end

    it 'should install the systemd unit' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/lib/systemd/system/fleet.service', '/tmp/build/lib/systemd/system/fleet.service')
      subject.build '/tmp/build'
    end
  end
end
