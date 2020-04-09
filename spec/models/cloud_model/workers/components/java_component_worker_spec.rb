# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::JavaComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::JavaComponentWorker.new host}
  
  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }
  
  describe 'build' do
    before do
      allow(subject).to receive :mkdir_p
      allow(subject).to receive :chroot!
    end
    
    it 'should make man directory' do
      expect(subject).to receive(:mkdir_p).with('/tmp/build/usr/share/man/man1/')
      
      subject.build '/tmp/build'
    end
    
    it 'should apt-get openjdk' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install openjdk-8-jre-headless -y', 'Failed to install java')
      
      subject.build '/tmp/build'
    end
  end
end