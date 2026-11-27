# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PerconaServerMongodbComponentWorker do
  let(:template) { double 'template', arch: 'amd64', os_version: 'debian-12' }
  let(:host) { double CloudModel::Host }
  subject { described_class.new template, host, component: CloudModel::Components::PerconaServerMongodbComponent.new(version: '7.0') }

  it { expect(subject.repository).to eq 'psmdb-70' }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
      allow(subject).to receive :chroot
    end

    it 'should add the line´s and the telemetry repository with the pinned Percona key' do
      expect(subject).to receive(:chroot!).with('/tmp/build', /search\\=0x4D1BB29D63D98E422B2113B19334A25F8507EFA5/, 'Failed to fetch Percona repository key')
      expect(subject).to receive(:chroot!).with('/tmp/build', %r{repo\.percona\.com/psmdb-70/apt\\ bookworm\\ main.* > /etc/apt/sources\.list\.d/percona-psmdb-70\.list}, 'Failed to add Percona psmdb-70 repository')
      expect(subject).to receive(:chroot!).with('/tmp/build', %r{repo\.percona\.com/telemetry/apt}, 'Failed to add Percona telemetry repository')
      subject.build '/tmp/build'
    end

    it 'should install the server non-interactively after the update' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update packages').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'DEBIAN_FRONTEND=noninteractive apt-get install percona-server-mongodb -y', 'Failed to install Percona Server for MongoDB 7.0').ordered
      subject.build '/tmp/build'
    end
  end
end
