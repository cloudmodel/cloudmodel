# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Redis do
  it { expect(subject).to be_a CloudModel::Services::Base }
  
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 6379 }
  it { expect(subject).to have_field(:redis_sentinel_port).of_type(Integer).with_default_value_of 26379 }
  it { expect(subject).to belong_to(:redis_sentinel_set).of_type(CloudModel::RedisSentinelSet) }
  
  describe 'kind' do
    it 'should return :redis' do
      expect(subject.kind).to eq :redis
    end
  end
  
  describe 'components_needed' do
    it 'should require only redis' do
      expect(subject.components_needed).to eq [:redis]
    end
  end
  
  describe 'service_status' do 
    pending
  end
  
  describe 'redis_sentinel_master?' do
    pending
  end
  
  describe 'redis_sentinel_slave?' do
    pending
  end
  
  describe 'redis_sentinel_set_version' do
    it 'is not available right now' do
      expect(subject.redis_sentinel_set_version).to eq 'N/A'
    end
  end
end