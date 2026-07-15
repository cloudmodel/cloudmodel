# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::NodejsComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  let(:component) {double CloudModel::Components::NodejsComponent, version: nil}
  subject {CloudModel::Workers::Components::NodejsComponentWorker.new template, host, component: component}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'nodeversion' do
    it 'should default to "22" when no version is set' do
      expect(subject.nodeversion).to eq '22'
    end

    it 'should return the component version when set' do
      allow(component).to receive(:version).and_return('20')
      expect(subject.nodeversion).to eq '20'
    end
  end

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should install Node.js from NodeSource for the default major' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'apt-get install -y ca-certificates curl gnupg && ' \
        'curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && ' \
        'apt-get install -y nodejs',
        'Failed to install Node.js'
      ).ordered

      subject.build '/tmp/build'
    end

    it 'should install Node.js from NodeSource for the given major' do
      allow(component).to receive(:version).and_return('20')
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'apt-get install -y ca-certificates curl gnupg && ' \
        'curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && ' \
        'apt-get install -y nodejs',
        'Failed to install Node.js'
      ).ordered

      subject.build '/tmp/build'
    end

    it 'should install yarn globally via npm' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build', 'npm install --global yarn', 'Failed to install yarn'
      ).ordered

      subject.build '/tmp/build'
    end
  end
end
