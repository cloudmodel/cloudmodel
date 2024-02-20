# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PhpComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::PhpComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get php and some default modules' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'add-apt-repository ppa:ondrej/php -y', 'Failed to add php ppa').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update apt').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install php8.2-fpm php8.2-curl php8.2-mbstring php8.2-zip php8.2-gd php8.2-dom php8.2-intl php8.2-bcmath php8.2-gmp php8.2-apcu -y', 'Failed to install packages for deployment of php app').ordered

      subject.build '/tmp/build'
    end
  end
end