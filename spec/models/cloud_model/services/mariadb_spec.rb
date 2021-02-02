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
    pending
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