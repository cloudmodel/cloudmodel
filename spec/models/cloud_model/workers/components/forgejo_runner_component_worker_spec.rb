# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::ForgejoRunnerComponentWorker do
  let(:template) {double 'template', arch: 'amd64'}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::ForgejoRunnerComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  it 'should default to the current runner release' do
    expect(subject.version).to eq '13.2.1'
  end

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
      allow(subject).to receive :chroot
      allow(subject).to receive :mkdir_p
      allow(subject).to receive :render_to_remote
    end

    it 'should install git (jobs check out with it) and gnupg' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install git git-lfs curl ca-certificates gnupg -y', 'Failed to install runner tooling')
      subject.build '/tmp/build'
    end

    it 'should create the forgejo-runner user with work, cache and gem directories' do
      expect(subject).to receive(:chroot!).with('/tmp/build', /adduser --system --home \/var\/lib\/forgejo-runner .* forgejo-runner/, 'Failed to create forgejo-runner user')
      expect(subject).to receive(:chroot!).with('/tmp/build', 'mkdir -p /etc/forgejo-runner /var/lib/forgejo-runner/cache /var/lib/forgejo-runner/work /var/lib/forgejo-runner/gems', 'Failed to create forgejo-runner directories')
      subject.build '/tmp/build'
    end

    it 'should download, verify and install the release binary for the template´s arch' do
      expect(subject).to receive(:chroot!).with('/tmp/build', %r{curl -fsSL https://code.forgejo.org/forgejo/runner/releases/download/v13.2.1/forgejo-runner-13.2.1-linux-amd64 -o /tmp/forgejo-runner && curl -fsSL .*\.asc -o /tmp/forgejo-runner.asc}, 'Failed to download forgejo-runner 13.2.1 (amd64)').ordered
      expect(CloudModel::Workers::Components::ReleaseSignature).to receive(:verify!).with(subject, '/tmp/build', 'EB114F5E6C0DC2BCDD183550A4B61A2DC5923710', '/tmp/forgejo-runner', 'forgejo-runner 13.2.1').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'install -m 755 /tmp/forgejo-runner /usr/local/bin/forgejo-runner && rm -f /tmp/forgejo-runner /tmp/forgejo-runner.asc', 'Failed to install forgejo-runner binary').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', '/usr/local/bin/forgejo-runner --version', 'forgejo-runner binary not runnable').ordered
      subject.build '/tmp/build'
    end

    it 'should install the systemd unit' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/lib/systemd/system/forgejo_runner.service', '/tmp/build/lib/systemd/system/forgejo_runner.service')
      subject.build '/tmp/build'
    end
  end
end
