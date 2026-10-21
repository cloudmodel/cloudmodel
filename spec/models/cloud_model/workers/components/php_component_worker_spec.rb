# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PhpComponentWorker do
  let(:template) {double os_version: 'debian-12'}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::PhpComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    let(:install_command) { "apt-get install php#{CloudModel.config.php_version}-fpm php#{CloudModel.config.php_version}-curl php#{CloudModel.config.php_version}-mbstring php#{CloudModel.config.php_version}-zip php#{CloudModel.config.php_version}-gd php#{CloudModel.config.php_version}-dom php#{CloudModel.config.php_version}-intl php#{CloudModel.config.php_version}-bcmath php#{CloudModel.config.php_version}-gmp php#{CloudModel.config.php_version}-apcu -y" }

    before do
      allow(subject).to receive :chroot!
    end

    it 'installs the configured php major from sury.org on Debian' do
      expect(subject).not_to receive(:chroot!).with('/tmp/build', 'add-apt-repository ppa:ondrej/php -y', 'Failed to add php ppa')
      expect(subject).to receive(:chroot!).with('/tmp/build', 'curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb && dpkg -i /tmp/debsuryorg-archive-keyring.deb && rm -f /tmp/debsuryorg-archive-keyring.deb', 'Failed to install the sury.org keyring').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', "echo 'deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ bookworm main' > /etc/apt/sources.list.d/php.list", 'Failed to add the sury.org php repository').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update apt').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', install_command, 'Failed to install packages for deployment of php app').ordered

      subject.build '/tmp/build'
    end

    it 'pins the source to the template release' do
      allow(template).to receive(:os_version).and_return 'debian-13'
      expect(subject).to receive(:chroot!).with('/tmp/build', /https:\/\/packages\.sury\.org\/php\/ trixie main/, 'Failed to add the sury.org php repository')

      subject.build '/tmp/build'
    end

    it 'installs the configured php major from the ondrej ppa on Ubuntu' do
      expect(template).to receive(:os_version).and_return 'ubuntu-24.04'
      expect(subject).not_to receive(:chroot!).with('/tmp/build', /sury/, anything)
      expect(subject).to receive(:chroot!).with('/tmp/build', 'add-apt-repository ppa:ondrej/php -y', 'Failed to add php ppa').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update apt').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', install_command, 'Failed to install packages for deployment of php app').ordered

      subject.build '/tmp/build'
    end

    it 'follows the configured php major' do
      allow(CloudModel.config).to receive(:php_version).and_return '8.3'
      expect(subject).to receive(:chroot!).with('/tmp/build', /apt-get install php8\.3-fpm php8\.3-curl .* php8\.3-apcu -y/, 'Failed to install packages for deployment of php app')

      subject.build '/tmp/build'
    end
  end
end
