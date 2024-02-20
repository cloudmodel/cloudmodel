# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::ImagemagickComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::ImagemagickComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get imagemagick' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install imagemagick -y', 'Failed to install packages for imagemagick')

      subject.build '/tmp/build'
    end
  end
end