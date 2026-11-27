# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PerconaServerComponentWorker do
  let(:template) { double 'template', arch: 'amd64', os_version: 'debian-12' }
  let(:host) { double CloudModel::Host }
  subject { CloudModel::Workers::Components::PerconaServerComponentWorker.new template, host }

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  it 'should default to the 8.4 LTS series' do
    expect(subject.series).to eq '8.4'
    expect(subject.repository).to eq 'ps-84-lts'
  end

  it 'should name the repository of the series pinned on the component' do
    worker = CloudModel::Workers::Components::PerconaServerComponentWorker.new template, host, component: CloudModel::Components::PerconaServerComponent.new(version: '8.0')
    expect(worker.repository).to eq 'ps-80'
  end

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
      allow(subject).to receive :chroot
    end

    it 'should fetch the Percona key by fingerprint and pin it' do
      expect(subject).to receive(:chroot!).with('/tmp/build', %r{curl -fsSL https://keyserver\.ubuntu\.com/pks/lookup\\\?op\\=get\\&search\\=0x4D1BB29D63D98E422B2113B19334A25F8507EFA5 \| gpg .*--dearmor > /usr/share/keyrings/percona-keyring\.gpg}, 'Failed to fetch Percona repository key').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', /test .*--show-keys .* = 4D1BB29D63D98E422B2113B19334A25F8507EFA5$/, /does not hold exactly the key/).ordered
      subject.build '/tmp/build'
    end

    it 'should add the server and the telemetry repository (the server package depends on the agent)' do
      expect(subject).to receive(:chroot!).with('/tmp/build', %r{http://repo\.percona\.com/ps-84-lts/apt\\ bookworm\\ main.* > /etc/apt/sources\.list\.d/percona-ps-84-lts\.list}, 'Failed to add Percona ps-84-lts repository')
      expect(subject).to receive(:chroot!).with('/tmp/build', %r{http://repo\.percona\.com/telemetry/apt\\ bookworm\\ main.* > /etc/apt/sources\.list\.d/percona-telemetry\.list}, 'Failed to add Percona telemetry repository')
      subject.build '/tmp/build'
    end

    it 'should install the server package non-interactively' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update packages').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'DEBIAN_FRONTEND=noninteractive apt-get install percona-server-server -y', 'Failed to install Percona Server 8.4').ordered
      subject.build '/tmp/build'
    end
  end
end
