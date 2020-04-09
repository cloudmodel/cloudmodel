# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::GuestChecks do
  let(:guest) { double CloudModel::Guest }
  subject { CloudModel::Monitoring::GuestChecks.new guest, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }
  
  describe 'indent_size' do
    it 'should indent by 2' do
      expect(subject.indent_size).to eq 2
    end
  end
  
  describe 'aquire_data' do
    it 'should aquire system and lxc info' do
      expect(guest).to receive(:system_info).and_return 'system info'
      expect(guest).to receive(:lxc_info).and_return 'lxc info'
      
      expect(subject.aquire_data).to eq system: 'system info', lxc: 'lxc info'
    end
  end
  
  describe 'check' do
    it 'should call check_system_info' do
      expect(subject).to receive(:check_system_info).and_return true
      expect(subject.check).to eq true
    end
  end
end