# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::BaseChecks do
  let(:host) {double CloudModel::Host, name: 'testhost'}
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Base, guest: guest }
  subject { CloudModel::Monitoring::Services::BaseChecks.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe 'acquire_data' do
    it 'should get services status' do
      status = double
      expect(service).to receive(:service_status).and_return status
      expect(subject.acquire_data).to eq status
    end
  end

  describe 'indent_size' do
    it 'should indent by 4' do
      expect(subject.indent_size).to eq 4
    end
  end

  describe 'line_prefix' do
    it 'should prefix host name before indention' do
      expect(subject.line_prefix).to eq '[testhost]     '
    end
  end

  describe 'sample_metrics' do
    it 'should flatten the numeric values from the service status' do
      allow(subject).to receive(:data).and_return('connections' => 12, 'memory' => {'used' => 2048}, 'version' => '7.2')
      expect(subject.sample_metrics).to eq 'connections' => 12.0, 'memory.used' => 2048.0
    end
  end

  describe 'check' do
    it 'should be a placeholder' do
      expect(subject.check).to eq nil
    end
  end
end