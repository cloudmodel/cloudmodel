# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::MongodbReplicationSetChecks do
  let(:mongodb_replication_set) { double CloudModel::MongodbReplicationSet }
  subject { CloudModel::Monitoring::MongodbReplicationSetChecks.new mongodb_replication_set, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe '.check' do
    it 'should check each active initiated replication set' do
      set1 = double CloudModel::MongodbReplicationSet, initiated?: true, active?: true
      allow(CloudModel::MongodbReplicationSet).to receive(:scoped).and_return([set1])
      checks_instance = double 'checks', check: true
      allow(CloudModel::Monitoring::MongodbReplicationSetChecks).to receive(:new).with(set1).and_return(checks_instance)
      allow(CloudModel::Monitoring::BaseChecks).to receive(:handle_cloudmodel_monitoring_exception).and_yield

      CloudModel::Monitoring::MongodbReplicationSetChecks.check
    end

    it 'should skip non-initiated sets' do
      set1 = double CloudModel::MongodbReplicationSet, initiated?: false, active?: true
      allow(CloudModel::MongodbReplicationSet).to receive(:scoped).and_return([set1])
      allow(CloudModel::Monitoring::BaseChecks).to receive(:handle_cloudmodel_monitoring_exception).and_yield

      expect(CloudModel::Monitoring::MongodbReplicationSetChecks).not_to receive(:new)
      CloudModel::Monitoring::MongodbReplicationSetChecks.check
    end

    it 'should skip inactive sets' do
      set1 = double CloudModel::MongodbReplicationSet, initiated?: true, active?: false
      allow(CloudModel::MongodbReplicationSet).to receive(:scoped).and_return([set1])
      allow(CloudModel::Monitoring::BaseChecks).to receive(:handle_cloudmodel_monitoring_exception).and_yield

      expect(CloudModel::Monitoring::MongodbReplicationSetChecks).not_to receive(:new)
      CloudModel::Monitoring::MongodbReplicationSetChecks.check
    end
  end

  describe 'acquire_data' do
    it 'should get set status' do
      allow(mongodb_replication_set).to receive(:status).and_return 'ok' => 1.0
      expect(subject.acquire_data).to eq 'ok' => 1.0
    end
  end

  describe 'line_prefix' do
    it 'should return "[_Mongo Repl_] "' do
      expect(subject.line_prefix).to eq "[_Mongo Repl_] "
    end
  end

  describe 'check' do
    it 'should be nil for no members' do
      allow(subject).to receive(:data).and_return 'ok' => 0.0
      expect(subject.check).to eq nil
    end

    it 'should be true for all members and set healthy' do
      expect(subject).to receive(:do_check).with(:set_health, 'Set Health', {critical: false}, message: "Set not healthy")
      expect(subject).to receive(:do_check).with(:member_health, "Members Health", {critical: false, warning: false}, {:message=>"Some Members or Arbiters are not healty"})
      allow(subject).to receive(:data).and_return 'ok' => 1.0, members: [{'health' => 1.0, 'stateStr' => 'PRIMARY'}]
      expect(subject.check).to eq true
    end

    it 'should be false for all members healthy and set not healthy' do
      expect(subject).to receive(:do_check).with(:set_health, 'Set Health', {critical: true}, message: "Set not healthy")
      expect(subject).to receive(:do_check).with(:member_health, "Members Health", {critical: false, warning: false}, {:message=>"Some Members or Arbiters are not healty"})
      allow(subject).to receive(:data).and_return 'ok' => 0.0, members: [{'health' => 1.0, 'stateStr' => 'PRIMARY'}]
      expect(subject.check).to eq false
    end

    it 'should be false for some members not healthy and set healthy' do
      expect(subject).to receive(:do_check).with(:set_health, 'Set Health', {critical: false}, message: "Set not healthy")
      expect(subject).to receive(:do_check).with(:member_health, "Members Health", {critical: false, warning: true}, {:message=>"Some Members or Arbiters are not healty"})
      allow(subject).to receive(:data).and_return 'ok' => 1.0, members: [{'health' => 1.0, 'stateStr' => 'PRIMARY'},{'health' => 1.0, 'stateStr' => 'SECONDARY'}, {'health' => 0.0, 'stateStr' => 'error'}]
      expect(subject.check).to eq false
    end

    it 'should be false for majority of members not healthy and set healthy' do
      expect(subject).to receive(:do_check).with(:set_health, 'Set Health', {critical: false}, message: "Set not healthy")
      expect(subject).to receive(:do_check).with(:member_health, "Members Health", {critical: true, warning: true}, {:message=>"Majority of operational members not healthy"})
      allow(subject).to receive(:data).and_return 'ok' => 1.0, members: [{'health' => 1.0, 'stateStr' => 'PRIMARY'},{'health' => 0.0, 'stateStr' => 'error'}, {'health' => 0.0, 'stateStr' => 'error'}]
      expect(subject.check).to eq false
    end

  end
end