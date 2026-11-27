# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::MysqlComponentWorker do
  let(:template) { double 'template', arch: 'amd64', os_version: 'debian-12' }
  let(:host) { double CloudModel::Host }
  subject { described_class.new template, host }

  it 'should default to the 8.4 LTS series' do
    expect(subject.series).to eq '8.4'
    expect(subject.repository).to eq 'mysql-8.4-lts'
  end

  it 'should name the 8.0 repository without the lts suffix' do
    worker = described_class.new template, host, component: CloudModel::Components::MysqlComponent.new(version: '8.0')
    expect(worker.repository).to eq 'mysql-8.0'
  end

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
      allow(subject).to receive :chroot
    end

    it 'should refuse architectures MySQL publishes no packages for' do
      allow(template).to receive(:arch).and_return 'arm64'
      expect(subject).not_to receive(:chroot!)
      expect { subject.build '/tmp/build' }.to raise_error(RuntimeError, /amd64 only, not for arm64/)
    end

    it 'should pin the MySQL release engineering key' do
      expect(subject).to receive(:chroot!).with('/tmp/build', /search\\=0xBCA43417C3B485DD128EC6D4B7B3B788A8D3785C .*> \/usr\/share\/keyrings\/mysql-keyring\.gpg/, 'Failed to fetch MySQL repository key').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', /test .* = BCA43417C3B485DD128EC6D4B7B3B788A8D3785C$/, /does not hold exactly the key/).ordered
      subject.build '/tmp/build'
    end

    it 'should add the series repository of the distribution' do
      expect(subject).to receive(:chroot!).with('/tmp/build', %r{http://repo\.mysql\.com/apt/debian\\ bookworm\\ mysql-8\.4-lts.* > /etc/apt/sources\.list\.d/mysql-8\.4-lts\.list}, 'Failed to add MySQL mysql-8.4-lts repository')
      subject.build '/tmp/build'
    end

    it 'should use the ubuntu tree on ubuntu templates' do
      allow(template).to receive(:os_version).and_return 'ubuntu-22.04'
      expect(subject).to receive(:chroot!).with('/tmp/build', %r{http://repo\.mysql\.com/apt/ubuntu\\ jammy\\ mysql-8\.4-lts}, anything)
      subject.build '/tmp/build'
    end

    it 'should install the community server non-interactively' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'DEBIAN_FRONTEND=noninteractive apt-get install mysql-community-server -y', 'Failed to install MySQL 8.4')
      subject.build '/tmp/build'
    end
  end
end
