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
    it 'should call check on each registered check' do
      check1 = double 'check1'
      check2 = double 'check2'
      CloudModel::Monitoring.instance_variable_set :@checks, [check1, check2]

      expect(check1).to receive(:check)
      expect(check2).to receive(:check)

      CloudModel::Monitoring.check
    end
  end
end