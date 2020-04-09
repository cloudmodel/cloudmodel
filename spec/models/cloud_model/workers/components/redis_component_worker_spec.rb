# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::RedisComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::RedisComponentWorker.new host}
  
  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }
  
  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end
    
    it 'should apt-get redis with sentinel' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install redis-server redis-sentinel -y', 'Failed to install Redis')
      
      subject.build '/tmp/build'
    end
  end
end