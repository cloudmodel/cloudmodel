# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::RedisSentinelSetChecks do
  let(:redis_sentinel_set) { double CloudModel::RedisSentinelSet }
  subject { CloudModel::Monitoring::RedisSentinelSetChecks.new redis_sentinel_set, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe '.check' do
    pending
  end

  describe 'acquire_data' do
    it 'should get set status' do
      allow(redis_sentinel_set).to receive(:status).and_return 'ok' => 1.0
      expect(subject.acquire_data).to eq 'ok' => 1.0
    end
  end

  describe 'line_prefix' do
    it 'should return "[_Redis Sentinel_] "' do
      expect(subject.line_prefix).to eq "[_Redis Sentinel_] "
    end
  end

  describe 'check' do
    pending
  end
end