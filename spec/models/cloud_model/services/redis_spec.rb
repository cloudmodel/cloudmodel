# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Redis do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 6379 }
  it { expect(subject).to have_field(:redis_sentinel_port).of_type(Integer).with_default_value_of 26379 }
  it { expect(subject).to belong_to(:redis_sentinel_set).of_type(CloudModel::RedisSentinelSet).with_optional }

  describe 'kind' do
    it 'should return :redis' do
      expect(subject.kind).to eq :redis
    end
  end

  describe 'allow_public_service?' do
    it 'should not allow public exposure' do
      expect(subject.allow_public_service?).to eq false
    end
  end

  describe 'public_service validation' do
    it 'should be invalid when marked as a public service' do
      subject.public_service = true
      subject.valid?
      expect(subject.errors[:public_service]).to be_present
    end

    it 'should be valid when not a public service' do
      subject.public_service = false
      subject.valid?
      expect(subject.errors[:public_service]).to be_blank
    end
  end

  describe 'components_needed' do
    it 'should require only redis' do
      expect(subject.components_needed).to eq [:redis]
    end
  end

  let(:guest) { double CloudModel::Guest, private_address: '10.42.0.1' }
  before { allow(subject).to receive(:guest).and_return(guest) }

  describe 'service_status' do
    it 'should return redis info with cleaned keys' do
      redis = double 'redis'
      allow(::Redis).to receive(:new).and_return(redis)
      allow(redis).to receive(:info).and_return({'connected_clients' => '5', 'redis_version' => '7.0', 'redis_mode' => 'standalone'})
      allow(redis).to receive(:close)

      result = subject.service_status
      expect(result['connected_clients']).to eq '5'
      expect(result).not_to have_key('redis_version')
      expect(result).not_to have_key('redis_mode')
    end

    it 'should return critical error on CannotConnectError' do
      redis = double 'redis'
      allow(::Redis).to receive(:new).and_return(redis)
      allow(redis).to receive(:info).and_raise(::Redis::CannotConnectError.new('Connection refused'))
      allow(redis).to receive(:close)

      result = subject.service_status
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :critical
    end

    it 'should return warning on other exceptions' do
      redis = double 'redis'
      allow(::Redis).to receive(:new).and_return(redis)
      allow(redis).to receive(:info).and_raise(RuntimeError.new('timeout'))
      allow(redis).to receive(:close)

      result = subject.service_status
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :warning
    end
  end

  describe 'redis_sentinel_master?' do
    it 'should return true if monitoring result role is master' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({'role' => 'master'})

      expect(subject.redis_sentinel_master?).to eq true
    end

    it 'should check sentinel set when no monitoring data' do
      allow(subject).to receive(:monitoring_last_check_result).and_return(nil)
      sentinel_set = double 'sentinel_set'
      allow(subject).to receive(:redis_sentinel_set).and_return(sentinel_set)
      allow(sentinel_set).to receive(:master_service).and_return(subject)

      expect(subject.redis_sentinel_master?).to eq true
    end

    it 'should return false when no sentinel set and no monitoring data' do
      allow(subject).to receive(:monitoring_last_check_result).and_return(nil)
      allow(subject).to receive(:redis_sentinel_set).and_return(nil)

      expect(subject.redis_sentinel_master?).to eq false
    end
  end

  describe 'redis_sentinel_slave?' do
    it 'should return inverse of redis_sentinel_master?' do
      allow(subject).to receive(:redis_sentinel_master?).and_return(true)
      expect(subject.redis_sentinel_slave?).to eq false

      allow(subject).to receive(:redis_sentinel_master?).and_return(false)
      expect(subject.redis_sentinel_slave?).to eq true
    end
  end

  describe 'redis_sentinel_set_version' do
    it 'is not available right now' do
      expect(subject.redis_sentinel_set_version).to eq 'N/A'
    end
  end
end