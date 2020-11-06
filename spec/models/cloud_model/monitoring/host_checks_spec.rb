# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::HostChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  subject { CloudModel::Monitoring::HostChecks.new host, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe 'line_prefix' do
    it 'should prefix host name before indention' do
      expect(subject.line_prefix).to eq '[testhost] '
    end
  end

  describe 'acquire_data' do
    it 'should acquire system info' do
      expect(host).to receive(:system_info).and_return 'system info'

      expect(subject.acquire_data).to eq system: 'system info'
    end
  end

  describe 'check_md' do
    pending
  end

  describe 'check_sensors' do
    pending
  end

  describe 'check_smart' do
    pending
  end

  describe 'check' do
    it 'should call check_system_info and check md, sensors, smart' do
      expect(subject).to receive(:check_system_info).and_return true

      expect(subject).to receive(:check_md).and_return true
      expect(subject).to receive(:check_sensors).and_return true
      expect(subject).to receive(:check_smart).and_return true

      expect(subject.check).to eq true
    end

    it 'should return false if system check fails' do
      expect(subject).to receive(:check_system_info).and_return false

      expect(subject).not_to receive(:check_md)
      expect(subject).not_to receive(:check_sensors)
      expect(subject).not_to receive(:check_smart)

      expect(subject.check).to eq false
    end
  end
end