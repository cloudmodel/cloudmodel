# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::RubyComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::RubyComponentWorker.new host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get ruby' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'add-apt-repository ppa:brightbox/ruby-ng -y', 'Failed to add ruby-ng ppa').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update apt').ordered

      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install ruby2.6 ruby2.6-dev ruby-switch git zlib1g-dev ruby-bcrypt nodejs -y', 'Failed to install packages for deployment of rails app')
      expect(subject).to receive(:chroot!).with('/tmp/build', 'gem install bundler', 'Failed to install current bundler')
      expect(subject).to receive(:chroot!).with('/tmp/build', "gem install bundler -v '~>1.0'", 'Failed to install legacy bundler v1')

      subject.build '/tmp/build'
    end
  end
end