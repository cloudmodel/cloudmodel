# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PhpComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::PhpComponentWorker.new host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get php' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install php-fpm -y', 'Failed to install packages for deployment of php app')

      subject.build '/tmp/build'
    end
  end
end