# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::WkhtmltopdfComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host, arch: '6502'}
  subject {CloudModel::Workers::Components::WkhtmltopdfComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    let(:uri) { double URI, read: '<a href="https://github.com/wkhtmltopdf/packaging/releases/download/0.42.23/wkhtmltox_0.42.23.bionic_6502.deb"><a href="https://github.com/wkhtmltopdf/packaging/releases/download/0.42.23/wkhtmltox_0.42.23.jammy_6502.deb">'}

    before do
      allow(subject).to receive :chroot!
      allow(URI).to receive(:parse).and_return uri
      allow(CloudModel.config).to receive(:ubuntu_short_name).and_return 'quick'
    end

    it 'should apt-get wkhtmltopdf dependencies' do
      allow(template).to receive(:os_version).and_return('ubuntu-18.04')
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install xfonts-75dpi xfonts-base fontconfig libjpeg-turbo8 libxrender1 -y', 'Failed to install packages for wkhtmltopdf dependencies')

      subject.build '/tmp/build'

    end

    it 'should install wkhtmltopdf for ubuntu 18.04' do
      allow(template).to receive(:os_version).and_return('ubuntu-18.04')
      expect(subject).to receive(:chroot!).with("/tmp/build", "wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.42.23/wkhtmltox_0.42.23.bionic_6502.deb && dpkg -i wkhtmltox_0.42.23.bionic_6502.deb && apt -f install", "Failed to install packages for wkhtmltopdf")

      subject.build '/tmp/build'
    end
    it 'should install wkhtmltopdf for ubuntu 22.04' do
      allow(template).to receive(:os_version).and_return('ubuntu-22.04')
      expect(subject).to receive(:chroot!).with("/tmp/build", "wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.42.23/wkhtmltox_0.42.23.jammy_6502.deb && dpkg -i wkhtmltox_0.42.23.jammy_6502.deb && apt -f install", "Failed to install packages for wkhtmltopdf")

      subject.build '/tmp/build'
    end
  end
end