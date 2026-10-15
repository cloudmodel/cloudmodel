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
      allow(subject).to receive :mkdir_p
      allow(subject).to receive :render_to_remote
    end

    it 'should install the git tooling' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install git git-lfs curl ca-certificates -y', 'Failed to install git tooling')
      subject.build '/tmp/build'
    end

    it 'should create the forgejo system user and its data/config layout' do
      expect(subject).to receive(:chroot!).with('/tmp/build', /adduser --system --home \/var\/lib\/forgejo .* forgejo/, 'Failed to create forgejo user')
      expect(subject).to receive(:chroot!).with('/tmp/build', /chown -R forgejo:forgejo \/var\/lib\/forgejo && chown root:forgejo \/etc\/forgejo/, 'Failed to set forgejo permissions')
      subject.build '/tmp/build'
    end

    it 'should download the release binary for the template´s arch (no apt repo: it has no arm64 builds)' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        %r{curl -fsSL https://codeberg.org/forgejo/forgejo/releases/download/v[^ ]+/forgejo-[^ ]+-linux-arm64 -o /usr/bin/forgejo && chmod 755 /usr/bin/forgejo},
        /Failed to download forgejo .* \(arm64\)/)
      expect(subject).to receive(:chroot!).with('/tmp/build', '/usr/bin/forgejo --version', 'Forgejo binary not runnable')
      subject.build '/tmp/build'
    end

    it 'should install the systemd unit' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/lib/systemd/system/forgejo.service', '/tmp/build/lib/systemd/system/forgejo.service')
      subject.build '/tmp/build'
    end
  end
end
