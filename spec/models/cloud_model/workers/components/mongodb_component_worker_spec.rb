# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::MongodbComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::MongodbComponentWorker.new host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get mongodb' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install libreadline5 mongodb -y', 'Failed to install mongodb')

      subject.build '/tmp/build'
    end
  end
end