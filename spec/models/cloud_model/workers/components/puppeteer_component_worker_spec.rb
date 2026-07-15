# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::PuppeteerComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  let(:component) {double CloudModel::Components::PuppeteerComponent, version: nil}
  subject {CloudModel::Workers::Components::PuppeteerComponentWorker.new template, host, component: component}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'installs the distro Chromium package' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'apt-get install chromium -y',
        'Failed to install Chromium'
      )

      subject.build '/tmp/build'
    end
  end
end
