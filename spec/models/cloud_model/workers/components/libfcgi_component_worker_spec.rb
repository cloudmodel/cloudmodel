# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::LibfcgiComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::LibfcgiComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get redis with sentinel' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install libfcgi0ldbl -y', 'Failed to install libfcgi')

      subject.build '/tmp/build'
    end
  end
end