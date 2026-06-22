# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::ForgejoComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::ForgejoComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should download the forgejo apt repo package' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'wget --content-disposition https://code.forgejo.org/forgejo-contrib/-/packages/debian/forgejo-deb-repo/0-0/files/2890',
        'Failed to get Forgejo apt repo')
      subject.build '/tmp/build'
    end

    it 'should install the forgejo apt repo package' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'apt-get install ./forgejo-deb-repo_0-0_all.deb',
        'Failed to install forgejo apt repo')
      subject.build '/tmp/build'
    end

    it 'should update package lists' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'apt-get update',
        'Failed to update packages')
      subject.build '/tmp/build'
    end

    it 'should install git, git-lfs and forgejo-bin' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'apt-get install git git-lfs forgejo-bin -y',
        'Failed to install forgejo')
      subject.build '/tmp/build'
    end
  end
end
