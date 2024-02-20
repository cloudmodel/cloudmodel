# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::XmlComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::XmlComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get libxml' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install libxml2-dev libxml2-utils libxslt-dev xsltproc -y', 'Failed to install packages for libxml')

      subject.build '/tmp/build'
    end
  end
end