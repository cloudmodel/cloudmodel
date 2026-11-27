# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Mixins::ServerPlatform do
  let(:host) { CloudModel::Host.new arch: 'arm64' }
  let(:guest) { CloudModel::Guest.new name: 'mongo', os_version: 'debian-13' }
  let(:table) do
    {
      'mongodb' => { '8.0' => { 'debian-12' => %w(amd64), 'ubuntu-22.04' => %w(amd64 arm64) } },
      'percona_server_mongodb' => { '7.0' => { 'debian-12' => %w(amd64) }, '8.0' => { 'debian-12' => %w(amd64), 'debian-13' => %w(amd64 arm64) } }
    }
  end
  subject { CloudModel::Services::Mongodb.new mongodb_version: '8.0' }

  before do
    allow(CloudModel::ComponentPlatforms).to receive(:table).and_return table
    allow(guest).to receive(:host).and_return host
    allow(subject).to receive(:guest).and_return guest
  end

  it 'offers only the pairs published for the guest´s OS and the host´s arch' do
    subject.mongodb_distribution = 'percona'
    expect(subject.available_servers).to eq [['percona', '8.0']]
  end

  it 'offers a new service only what is published and preselects the first' do
    expect(subject.available_servers).to eq [['percona', '8.0']]
    expect(subject.selected_server).to eq 'percona:8.0'
  end

  it 'keeps the current pair of a stored service in the offer even when it is not published' do
    allow(subject).to receive(:persisted?).and_return true
    expect(subject.available_servers).to eq [['percona', '8.0'], ['mongodb', '8.0']]
    expect(subject.selected_server).to eq 'mongodb:8.0'
  end

  it 'rejects a new service on a combination the vendor does not publish' do
    expect(subject).not_to be_valid
    expect(subject.errors[:mongodb_version].first).to eq 'mongodb 8.0 is not published for debian-13 on arm64 (available here: percona 8.0)'
  end

  it 'accepts a published combination' do
    subject.server = 'percona:8.0'
    expect(subject.mongodb_distribution).to eq 'percona'
    expect(subject.server).to eq 'percona:8.0'
    expect(subject).to be_valid
  end

  it 'leaves a stored service alone until its server or the guest´s OS changes' do
    allow(subject).to receive(:new_record?).and_return false
    allow(subject).to receive(:mongodb_version_changed?).and_return false
    allow(subject).to receive(:mongodb_distribution_changed?).and_return false
    allow(guest).to receive(:os_version_changed?).and_return false
    expect(subject).to be_valid

    allow(guest).to receive(:os_version_changed?).and_return true
    expect(subject).not_to be_valid
  end

  it 'does not restrict a guest without a host' do
    allow(guest).to receive(:host).and_return nil
    expect(subject).to be_valid
  end

  it 'applies to the MySQL service with the default series' do
    mysql = CloudModel::Services::Mysql.new mysql_distribution: 'mysql'
    allow(mysql).to receive(:guest).and_return guest
    allow(CloudModel::ComponentPlatforms).to receive(:table).and_return('mysql' => { '8.4' => { 'debian-13' => %w(amd64) } }, 'percona_server' => { '8.4' => { 'debian-13' => %w(amd64 arm64) } })
    expect(mysql).not_to be_valid
    expect(mysql.available_servers).to eq [['percona', '8.4']]
    mysql.server = 'percona:8.4'
    expect(mysql).to be_valid
  end
end
