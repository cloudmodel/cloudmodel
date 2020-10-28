# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::WkhtmltopdfComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::WkhtmltopdfComponentWorker.new host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get wkhtmltopdf' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install wkhtmltopdf -y', 'Failed to install packages for wkhtmltopdf')

      subject.build '/tmp/build'
    end
  end
end