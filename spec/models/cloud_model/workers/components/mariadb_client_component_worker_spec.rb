# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::MariadbClientComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::MariadbClientComponentWorker.new host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get mariadb client' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install mariadb-client -y', 'Failed to install mariadb client')

      subject.build '/tmp/build'
    end
  end
end