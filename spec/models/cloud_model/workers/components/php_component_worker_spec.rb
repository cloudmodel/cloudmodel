# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PhpComponentWorker do
  let(:template) {double os_version: 'debian-12'}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::PhpComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get php and some default modules on Debian without ppa' do
      expect(subject).not_to receive(:chroot!).with('/tmp/build', 'add-apt-repository ppa:ondrej/php -y', 'Failed to add php ppa')
      expect(subject).not_to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update apt')
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install php8.3-fpm php8.3-curl php8.3-mbstring php8.3-zip php8.3-gd php8.3-dom php8.3-intl php8.3-bcmath php8.3-gmp php8.3-apcu -y', 'Failed to install packages for deployment of php app')

      subject.build '/tmp/build'
    end

    it 'should apt-get php and some default modules on Ubuntu with ppa' do
      expect(template).to receive(:os_version).and_return 'ubuntu-24.04'
      expect(subject).to receive(:chroot!).with('/tmp/build', 'add-apt-repository ppa:ondrej/php -y', 'Failed to add php ppa').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update apt').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install php8.3-fpm php8.3-curl php8.3-mbstring php8.3-zip php8.3-gd php8.3-dom php8.3-intl php8.3-bcmath php8.3-gmp php8.3-apcu -y', 'Failed to install packages for deployment of php app').ordered

      subject.build '/tmp/build'
    end
  end
end