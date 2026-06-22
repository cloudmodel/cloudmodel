# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::JitsiComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::JitsiComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
      allow(subject).to receive(:puts)
    end

    it 'should add the prosody apt repository key and source' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'curl -sL https://prosody.im/files/prosody-debian-packages.key -o /etc/apt/keyrings/prosody-debian-packages.key',
        'Failed to add prosody key'
      )
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        "echo \"deb [signed-by=/etc/apt/keyrings/prosody-debian-packages.key] http://packages.prosody.im/debian $(lsb_release -sc) main\" | tee /etc/apt/sources.list.d/prosody-debian-packages.list",
        'Failed to add prosody source'
      )

      subject.build '/tmp/build'
    end

    it 'should add the jitsi apt repository key and source' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        "curl -sL https://download.jitsi.org/jitsi-key.gpg.key | sh -c 'gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg'",
        'Failed to add jitsi key'
      )
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        "echo \"deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/\" | tee /etc/apt/sources.list.d/jitsi-stable.list",
        'Failed to add jitsi source'
      )

      subject.build '/tmp/build'
    end

    it 'should update apt' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update packages')

      subject.build '/tmp/build'
    end

    it 'should install lua 5.2' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install lua5.2 -y', 'Failed to install lua 5.2')

      subject.build '/tmp/build'
    end
  end
end
