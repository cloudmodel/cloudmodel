# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Mongodb do
  it { expect(subject).to be_a CloudModel::Services::Base }
  
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 27017 }
  it { expect(subject).to belong_to(:mongodb_replication_set).of_type(CloudModel::MongodbReplicationSet) }
  
  context 'kind' do
    it 'should return :mongodb' do
      expect(subject.kind).to eq :mongodb
    end
  end
  
  context 'components_needed' do
    it 'should require only mongodb' do
      expect(subject.components_needed).to eq [:mongodb]
    end
  end

  context 'sanitize_service_data' do
    pending
  end

  context 'service_status' do
    pending
  end

  context 'mongodb_replication_set_master?' do
    pending
  end

  context 'mongodb_replication_set_version' do
    pending
  end

  context 'backupable?' do
    it 'should be true' do
      expect(subject.backupable?).to eq true
    end
  end

  context 'backup' do
    pending
  end

  context 'restore' do
    pending
  end
end