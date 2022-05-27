# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::RubyComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::RubyComponentWorker.new host, component: double(CloudModel::Components::RubyComponent, version: '4.2')}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'rubyversion' do
    it "should return components ruby version" do
      expect(subject.rubyversion).to eq '4.2'
    end

    it "should default to CloudModel.config.ruby_version" do
      subject.instance_variable_set '@options', {}
      expect(subject.rubyversion).to eq CloudModel.config.ruby_version
    end
  end

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it "should install RVM with given ruby version" do
      expect(subject).to receive(:chroot).with('/tmp/build', "gpg --keyserver hkp://keys.openpgp.org --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB").ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install git zlib1g-dev curl bcrypt nodejs -y', 'Failed to install packages for deployment of rails app').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', "curl -sSL https://get.rvm.io | bash -s master --ruby=ruby-4.2", "Failed to install RVM").ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'gem install bundler', 'Failed to install current bundler')
      expect(subject).to receive(:chroot!).with('/tmp/build', "gem install bundler -v '~>1.0'", 'Failed to install legacy bundler v1')

      subject.build '/tmp/build'
    end
  end
end