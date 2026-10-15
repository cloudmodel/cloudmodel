# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring do
  describe '.register_check' do
    it 'should add a check to the checks list' do
      check = double 'check'
      CloudModel::Monitoring.register_check check
      expect(CloudModel::Monitoring.instance_variable_get(:@checks)).to include(check)
    end
  end

  describe '.check' do
    it 'should call check on each registered check group, each isolated by name' do
      check1 = double 'check1', name: 'Monitoring::Check1Checks'
      check2 = double 'check2', name: 'Monitoring::Check2Checks'
      CloudModel::Monitoring.instance_variable_set :@checks, [check1, check2]

      expect(check1).to receive(:check)
      expect(check2).to receive(:check)

      CloudModel::Monitoring.check
    end

    it 'should keep going when one check group crashes' do
      check1 = double 'check1', name: 'Monitoring::BrokenChecks'
      check2 = double 'check2', name: 'Monitoring::FineChecks'
      CloudModel::Monitoring.instance_variable_set :@checks, [check1, check2]
      allow(check1).to receive(:check).and_raise('driver unreachable')
      allow(CloudModel::Monitoring::BaseChecks).to receive(:handle_cloudmodel_monitoring_exception) { |&blk| blk.call rescue nil }

      expect(check2).to receive(:check)
      CloudModel::Monitoring.check
    end
  end
end