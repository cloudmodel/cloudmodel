# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Mariadb do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 3306 }
  it { expect(subject).to have_field(:mariadb_galera_port).of_type(Integer).with_default_value_of 4567 }

  it { expect(subject).to belong_to(:mariadb_galera_cluster).of_type(CloudModel::MariadbGaleraCluster).with_optional }

  describe 'kind' do
    it 'should return :mariadb' do
      expect(subject.kind).to eq :mariadb
    end
  end

  describe 'components_needed' do
    it 'should require only mariadb' do
      expect(subject.components_needed).to eq [:mariadb]
    end
  end

  describe 'service_status' do
    let(:client) {double close:true, query:[]}

    before do
      allow(subject).to receive(:guest).and_return double private_address: '10.42.23.1'
      allow(Mysql2::Client).to receive(:new).with(host: '10.42.23.1', username: 'monitoring').and_return client
    end

    it 'should get mysql status' do
      expect(Mysql2::Client).to receive(:new).with(host: '10.42.23.1', username: 'monitoring').and_return client
      expect(client).to receive(:query).with("SHOW STATUS")

      subject.service_status
    end

    it 'should transform mysql result as hash' do
      expect(client).to receive(:query).with("SHOW STATUS").and_return [
        {'Variable_name' => 'some_item', 'Value' => 'some value'},
        {'Variable_name' => 'some_other_item', 'Value' => 'some other value'},
      ]
      expect(subject.service_status).to eq(
        'some_item' => 'some value',
        'some_other_item' => 'some other value',
      )
    end

    it 'should close the mysql client connection' do
      expect(client).to receive(:close)
      subject.service_status
    end

    it 'should return error with exception' do
      allow(Mysql2::Client).to receive(:new).and_raise 'DB not connectable'
      expect(subject.service_status).to eq(
        error: "Failed to get db status\nRuntimeError\n\nDB not connectable",
        key: :not_reachable,
        severity: :critical
      )
    end
  end

  describe 'backupable?' do
    it 'should be true' do
      expect(subject.backupable?).to eq true
    end
  end

  describe 'backup' do
    pending
  end

  describe 'restore' do
    pending
  end
end