# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PhpMysqlComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::PhpMysqlComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get mariadb php module' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install php8.3-mysql -y', 'Failed to install php mysql module')

      subject.build '/tmp/build'
    end
  end
end