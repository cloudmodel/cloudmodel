# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::MariadbComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::MariadbComponentWorker.new host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get mariadb' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install mariadb-server galera-arbitrator-4 -y', 'Failed to install mariadb')

      subject.build '/tmp/build'
    end
  end
end