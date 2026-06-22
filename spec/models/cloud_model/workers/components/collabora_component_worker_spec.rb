# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::CollaboraComponentWorker do
  let(:template) {double os_version: 'ubuntu-22.04'}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::CollaboraComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe '_prepare_collabora_repository' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should install key management, add the repo and the key' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get install dirmngr gnupg -y", "Failed to install key management")
      expect(subject).to receive(:chroot!).with('/tmp/build', "echo 'deb https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-ubuntu1804 ./' | sudo tee /etc/apt/sources.list.d/collabora.list", "Failed to add collabora to list if repos")
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0C54D189F4BA284D", "Failed to add collabora key")

      subject._prepare_collabora_repository '/tmp/build'
    end
  end

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should prepare the repository' do
      expect(subject).to receive(:_prepare_collabora_repository).with('/tmp/build')

      subject.build '/tmp/build'
    end

    it 'should update packages' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get update", "Failed to update packages")

      subject.build '/tmp/build'
    end

    it 'should install coolwsd on non-bionic releases' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get install apt-transport-https ca-certificates coolwsd code-brand -y", "Failed to install collabora")

      subject.build '/tmp/build'
    end

    it 'should install loolwsd on Bionic Beaver' do
      allow(template).to receive(:os_version).and_return 'ubuntu-18.04'

      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get install apt-transport-https ca-certificates loolwsd code-brand -y", "Failed to install collabora")

      subject.build '/tmp/build'
    end
  end
end
