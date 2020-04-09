# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::HostChecks do
  let(:host) { double CloudModel::Host }
  subject { CloudModel::Monitoring::HostChecks.new host, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }
  
  describe 'aquire_data' do
    it 'should aquire system info' do
      expect(host).to receive(:system_info).and_return 'system info'
      
      expect(subject.aquire_data).to eq system: 'system info'
    end
  end
  
  describe 'check' do
    it 'should call check_system_info' do
      expect(subject).to receive(:check_system_info).and_return true
      
      allow(subject).to receive(:data).and_return({})
      
      expect(subject.check).to eq true
    end
  end
end