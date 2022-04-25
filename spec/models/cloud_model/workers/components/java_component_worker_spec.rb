# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::JavaComponentWorker do
  let(:host) {double CloudModel::Host}
  let(:component) {double CloudModel::Components::JavaComponent, version: nil}
  subject {CloudModel::Workers::Components::JavaComponentWorker.new host, component: component}

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
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install default-jre-headless -y', 'Failed to install Java')

      subject.build '/tmp/build'
    end

    it 'should apt-get openjdk with given version 8' do
      allow(component).to receive(:version).and_return('8')
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install openjdk-8-jre-headless -y', 'Failed to install Java 8')

      subject.build '/tmp/build'
    end

    it 'should apt-get openjdk with given version 11' do
      allow(component).to receive(:version).and_return('11')
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install openjdk-11-jre-headless -y', 'Failed to install Java 11')

      subject.build '/tmp/build'
    end
  end
end