# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::GitleaksComponentWorker do
  let(:template) {double 'template', arch: 'amd64'}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::GitleaksComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  it 'should default to the pinned release and name the amd64 tarball x64' do
    expect(subject.version).to eq '8.30.1'
    expect(subject.release_arch).to eq 'x64'
  end

  describe 'build' do
    before { allow(subject).to receive :chroot! }

    it 'should download the tarball, verify the pinned checksum and install the binary' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'curl -fsSL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz -o /tmp/gitleaks.tar.gz', 'Failed to download gitleaks 8.30.1 (amd64)').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', /echo 551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb\\ \\ \/tmp\/gitleaks.tar.gz \| sha256sum -c --quiet -/, /Checksum of gitleaks 8.30.1/).ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', /install -m 755 \/tmp\/gitleaks \/usr\/local\/bin\/gitleaks/, 'Failed to install gitleaks binary').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', '/usr/local/bin/gitleaks version', 'gitleaks binary not runnable').ordered
      subject.build '/tmp/build'
    end

    it 'should refuse a release without a pinned checksum' do
      worker = described_class.new template, host, component: CloudModel::Components::GitleaksComponent.new(version: '9.9.9')
      expect { worker.build '/tmp/build' }.to raise_error(/No pinned checksum for gitleaks 9.9.9/)
    end
  end
end
