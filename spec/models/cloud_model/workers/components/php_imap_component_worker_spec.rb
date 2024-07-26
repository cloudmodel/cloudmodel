# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PhpImapComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::PhpImapComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get mariadb php module' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install php8.3-imap -y', 'Failed to install php imap module')

      subject.build '/tmp/build'
    end
  end
end