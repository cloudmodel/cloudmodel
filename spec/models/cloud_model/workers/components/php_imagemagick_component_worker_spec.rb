# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PhpImagemagickComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::PhpImagemagickComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get imagemagick php module' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install php8.3-imagick -y', 'Failed to install php imagemagick module')

      subject.build '/tmp/build'
    end
  end
end