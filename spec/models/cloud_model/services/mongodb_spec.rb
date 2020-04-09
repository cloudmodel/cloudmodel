# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Mongodb do
  it { expect(subject).to be_a CloudModel::Services::Base }
  
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 27017 }
  it { expect(subject).to belong_to(:mongodb_replication_set).of_type(CloudModel::MongodbReplicationSet) }
  
  describe 'kind' do
    it 'should return :mongodb' do
      expect(subject.kind).to eq :mongodb
    end
  end
  
  describe 'components_needed' do
    it 'should require only mongodb' do
      expect(subject.components_needed).to eq [:mongodb]
    end
  end

  describe 'sanitize_service_data' do
    pending
  end

  describe 'service_status' do
    pending
  end

  describe 'mongodb_replication_set_master?' do
    pending
  end

  describe 'mongodb_replication_set_version' do
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