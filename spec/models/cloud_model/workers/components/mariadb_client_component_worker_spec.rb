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

    it 'should add mariadb dep repo' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get install curl -y", "Failed to install curl").ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', "curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash", "Failed to setup mariadb repository").ordered

      subject.build '/tmp/build'
    end

    it 'should apt-get mariadb client' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install mariadb-client -y', 'Failed to install mariadb client')

      subject.build '/tmp/build'
    end
  end
end