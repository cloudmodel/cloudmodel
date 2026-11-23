# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::RubyComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::RubyComponentWorker.new template, host, component: double(CloudModel::Components::RubyComponent, version: nil)}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    it 'installs the runtime libraries and build dependencies, no Ruby and no RVM' do
      allow(template).to receive(:os_version).and_return 'debian-12'
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install git curl ca-certificates build-essential libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev libgdbm-dev libgmp-dev -y', /Ruby runtime libraries/)
      expect(subject).not_to receive(:chroot!).with(anything, /rvm|get.rvm.io/, anything)
      subject.build '/tmp/build'
    end

    it 'adds bcrypt on Ubuntu 18.04' do
      allow(template).to receive(:os_version).and_return 'ubuntu-18.04'
      expect(subject).to receive(:chroot!).with('/tmp/build', /libgmp-dev bcrypt -y\z/, anything)
      subject.build '/tmp/build'
    end
  end
end
