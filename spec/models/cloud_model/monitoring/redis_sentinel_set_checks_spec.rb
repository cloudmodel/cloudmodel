# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::RedisSentinelSetChecks do
  let(:redis_sentinel_set) { double CloudModel::RedisSentinelSet }
  subject { CloudModel::Monitoring::RedisSentinelSetChecks.new redis_sentinel_set, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe '.check' do
    it 'should check each active sentinel set' do
      set1 = double CloudModel::RedisSentinelSet, active?: true
      allow(CloudModel::RedisSentinelSet).to receive(:scoped).and_return([set1])
      checks_instance = double 'checks', check: true
      allow(CloudModel::Monitoring::RedisSentinelSetChecks).to receive(:new).with(set1).and_return(checks_instance)
      allow(CloudModel::Monitoring::BaseChecks).to receive(:handle_cloudmodel_monitoring_exception).and_yield

      CloudModel::Monitoring::RedisSentinelSetChecks.check
    end

    it 'should skip inactive sets' do
      set1 = double CloudModel::RedisSentinelSet, active?: false
      allow(CloudModel::RedisSentinelSet).to receive(:scoped).and_return([set1])
      allow(CloudModel::Monitoring::BaseChecks).to receive(:handle_cloudmodel_monitoring_exception).and_yield

      expect(CloudModel::Monitoring::RedisSentinelSetChecks).not_to receive(:new)
      CloudModel::Monitoring::RedisSentinelSetChecks.check
    end
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
    it 'should check set health as ok when reachable' do
      allow(subject).to receive(:data).and_return({key: :ok})
      expect(subject).to receive(:do_check).with(:set_health, 'Set Health', {critical: false}, message: "Set not healthy")

      subject.check
    end

    it 'should check set health as critical when not reachable' do
      allow(subject).to receive(:data).and_return({key: :not_reachable})
      expect(subject).to receive(:do_check).with(:set_health, 'Set Health', {critical: true}, message: "Set not healthy")

      subject.check
    end

    it 'should return data' do
      test_data = {key: :ok}
      allow(subject).to receive(:data).and_return(test_data)
      allow(subject).to receive(:do_check)

      expect(subject.check).to eq test_data
    end
  end
end