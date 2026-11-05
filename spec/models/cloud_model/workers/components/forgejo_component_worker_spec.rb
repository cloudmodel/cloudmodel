# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::ForgejoComponentWorker do
  let(:template) {double 'template', arch: 'arm64'}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::ForgejoComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
      allow(subject).to receive :chroot
      allow(subject).to receive :mkdir_p
      allow(subject).to receive :render_to_remote
    end

    it 'should install the git tooling and gnupg for the signature check' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install git git-lfs curl ca-certificates gnupg -y', 'Failed to install git tooling')
      subject.build '/tmp/build'
    end

    it 'should default to the current LTS release' do
      expect(subject.version).to eq '15.0.11'
    end

    it 'should install the release pinned on the component' do
      worker = CloudModel::Workers::Components::ForgejoComponentWorker.new template, host, component: CloudModel::Components::ForgejoComponent.new(version: '15.0.12')
      expect(worker.version).to eq '15.0.12'
    end

    it 'should create the forgejo system user and its data/config layout' do
      expect(subject).to receive(:chroot!).with('/tmp/build', /adduser --system --home \/var\/lib\/forgejo .* forgejo/, 'Failed to create forgejo user')
      expect(subject).to receive(:chroot!).with('/tmp/build', /chown -R forgejo:forgejo \/var\/lib\/forgejo && chown root:forgejo \/etc\/forgejo/, 'Failed to set forgejo permissions')
      subject.build '/tmp/build'
    end

    it 'should download the release binary and its signature for the template´s arch (no apt repo: it has no arm64 builds)' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        %r{curl -fsSL https://codeberg.org/forgejo/forgejo/releases/download/v15.0.11/forgejo-15.0.11-linux-arm64 -o /tmp/forgejo && curl -fsSL https://codeberg.org/forgejo/forgejo/releases/download/v15.0.11/forgejo-15.0.11-linux-arm64.asc -o /tmp/forgejo.asc},
        /Failed to download forgejo 15.0.11 \(arm64\)/)
      expect(subject).to receive(:chroot!).with('/tmp/build', '/usr/bin/forgejo --version', 'Forgejo binary not runnable')
      subject.build '/tmp/build'
    end

    it 'should verify the release signature before installing the binary' do
      expect(CloudModel::Workers::Components::ReleaseSignature).to receive(:verify!).with(subject, '/tmp/build', 'EB114F5E6C0DC2BCDD183550A4B61A2DC5923710', '/tmp/forgejo', 'forgejo 15.0.11').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'install -m 755 /tmp/forgejo /usr/bin/forgejo && rm -f /tmp/forgejo /tmp/forgejo.asc', 'Failed to install forgejo binary').ordered
      subject.build '/tmp/build'
    end

    it 'should install the systemd unit' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/lib/systemd/system/forgejo.service', '/tmp/build/lib/systemd/system/forgejo.service')
      subject.build '/tmp/build'
    end
  end
end
