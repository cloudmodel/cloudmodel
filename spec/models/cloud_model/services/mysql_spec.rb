# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Mysql do
  let(:guest) { CloudModel::Guest.new name: 'db06' }
  before { allow(subject).to receive(:guest).and_return guest }

  it { expect(subject).to be_a CloudModel::Services::Base }
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 3306 }
  it { expect(subject).to have_field(:mysql_version).of_type(String) }
  it { expect(subject).to have_field(:mysql_distribution).of_type(String).with_default_value_of 'percona' }
  it { expect(subject).to validate_inclusion_of(:mysql_distribution).to_allow('mysql', 'percona') }
  it { expect(subject).to have_field(:telemetry).of_type(Mongoid::Boolean).with_default_value_of false }

  it { expect(subject.kind).to eq :mysql }
  it { expect(subject.allow_public_service?).to eq false }
  it { expect(subject.backupable?).to eq true }
  it { expect(subject.backup_data_mount_point).to eq 'var/lib/mysql' }

  describe 'components_needed' do
    it 'should require the 8.4 LTS series by default' do
      expect(subject.components_needed).to eq [:"percona_server@8.4"]
    end

    it 'should install MySQL Community of the series for the mysql distribution' do
      subject.mysql_distribution = 'mysql'
      expect(subject.components_needed).to eq [:"mysql@8.4"]
    end

    it 'should pin the series set on the service' do
      subject.mysql_version = '8.0'
      expect(subject.components_needed).to eq [:"percona_server@8.0"]
    end
  end

  describe 'validation' do
    it 'should refuse a guest with a MariaDB service' do
      guest.services << CloudModel::Services::Mariadb.new
      expect(subject).not_to be_valid
      expect(subject.errors[:base]).to include 'cannot run in a guest with a MariaDB service'
    end

    it 'should be valid on its own' do
      expect(subject).to be_valid
    end
  end

  describe 'service_status' do
    it 'should report alive when mysqladmin answers' do
      expect(guest).to receive(:exec).with('mysqladmin ping --silent').and_return [true, '']
      expect(subject.service_status).to eq(alive: true)
    end

    it 'should report an unreachable server' do
      allow(guest).to receive(:exec).and_return [false, 'connect failed']
      expect(subject.service_status).to include(key: :not_reachable, severity: :critical)
    end
  end
end
