# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PhpComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::PhpComponentWorker.new host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get php and some default modules' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install software-properties-common -y', 'Failed to install software-properties-common for php ppa').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'add-apt-repository ppa:ondrej/php -y', 'Failed to add php ppa').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update apt').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install php7.4-fpm php7.4-curl php7.4-mbstring php7.4-zip php7.4-gd php7.4-dom php7.4-intl php7.4-bcmath php7.4-gmp php7.4-apcu php7.4-apcu-bc -y', 'Failed to install packages for deployment of php app').ordered

      subject.build '/tmp/build'
    end
  end
end