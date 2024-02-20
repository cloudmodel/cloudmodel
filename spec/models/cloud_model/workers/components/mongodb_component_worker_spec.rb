# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::MongodbComponentWorker do
  let(:template) {double os_version: 'ubuntu-22.04'}
  let(:host) {double CloudModel::Host}
  let(:component) {double CloudModel::Components::MongodbComponent, version: nil}
  subject {CloudModel::Workers::Components::MongodbComponentWorker.new template, host, component: component}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get mongodb-org with default version 6.0' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get install gnupg -y", "Failed to install key management")

      expect(subject).to receive(:chroot!).with('/tmp/build', "wget -q -O - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add - ", "Failed to add mongodb key")

      expect(subject).to receive(:chroot!).with('/tmp/build', "echo 'deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse' | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list", "Failed to add mongodb to list if repos")

      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get update", "Failed to update packages")


      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install mongodb-org -y', 'Failed to install mongodb')

      subject.build '/tmp/build'
    end

    it 'should apt-get mongodb-org with specified version' do
      allow(template).to receive(:os_version).and_return 'ubuntu-18.04'
      allow(component).to receive(:version).and_return('5.6')

      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get install gnupg -y", "Failed to install key management")

      expect(subject).to receive(:chroot!).with('/tmp/build', "wget -q -O - https://www.mongodb.org/static/pgp/server-5.6.asc | sudo apt-key add - ", "Failed to add mongodb key")

      expect(subject).to receive(:chroot!).with('/tmp/build', "echo 'deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/5.6 multiverse' | sudo tee /etc/apt/sources.list.d/mongodb-org-5.6.list", "Failed to add mongodb to list if repos")

      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get update", "Failed to update packages")


      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install libreadline5 mongodb-org -y', 'Failed to install mongodb')

      subject.build '/tmp/build'
    end
  end
end