# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::MsCoreFontsComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::MsCoreFontsComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should pre-seed debconf to accept the MS Core Fonts EULA' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections',
        'Failed to accept MS Core Fonts Licence'
      )

      subject.build '/tmp/build'
    end

    it 'should apt-get ttf-mscorefonts-installer' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'apt-get install ttf-mscorefonts-installer',
        'Failed to install MS Core Fonts'
      )

      subject.build '/tmp/build'
    end
  end
end
