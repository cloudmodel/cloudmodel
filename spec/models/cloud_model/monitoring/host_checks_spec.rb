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
    it 'should check RAID status when md data is present' do
      allow(subject).to receive(:data).and_return({system: {'md' => {'devs' => {'md0' => {'status' => 'active'}, 'md1' => {'status' => 'active'}, 'md2' => {'status' => 'active'}, 'md3' => {'status' => 'active'}, 'md4' => {'status' => 'active'}}}}})
      expect(subject).to receive(:do_check).with(:mdtools, 'RAID', {critical: false}, message: '')

      subject.check_md
    end

    it 'should report missing md devices' do
      allow(subject).to receive(:data).and_return({system: {'md' => {'devs' => {'md0' => {'status' => 'active'}}}}})
      expect(subject).to receive(:do_check).with(:mdtools, 'RAID', {critical: true}, hash_including(:message))

      subject.check_md
    end

    it 'should report inactive md devices' do
      allow(subject).to receive(:data).and_return({system: {'md' => {'devs' => {'md0' => {'status' => 'active'}, 'md1' => {'status' => 'inactive'}, 'md2' => {'status' => 'active'}, 'md3' => {'status' => 'active'}, 'md4' => {'status' => 'active'}}}}})
      expect(subject).to receive(:do_check).with(:mdtools, 'RAID', {critical: true}, hash_including(:message))

      subject.check_md
    end

    it 'should do nothing when no md data' do
      allow(subject).to receive(:data).and_return({system: {}})
      expect(subject).not_to receive(:do_check)

      subject.check_md
    end
  end

  describe 'check_sensors' do
    it 'should check sensors when data is present' do
      allow(subject).to receive(:data).and_return({system: {'sensors' => {'temp1' => {'input' => 50.0, 'max' => 100.0, 'min' => 0.0}}}})
      expect(subject).to receive(:do_check).with(:sensors, 'Sensors', {warning: false}, message: '')

      subject.check_sensors
    end

    it 'should report sensor above max' do
      allow(subject).to receive(:data).and_return({system: {'sensors' => {'temp1' => {'input' => 110.0, 'max' => 100.0}}}})
      expect(subject).to receive(:do_check).with(:sensors, 'Sensors', {warning: true}, hash_including(:message))

      subject.check_sensors
    end

    it 'should report sensor below min' do
      allow(subject).to receive(:data).and_return({system: {'sensors' => {'fan1' => {'input' => 0.0, 'min' => 500.0}}}})
      expect(subject).to receive(:do_check).with(:sensors, 'Sensors', {warning: true}, hash_including(:message))

      subject.check_sensors
    end

    it 'should do nothing when no sensor data' do
      allow(subject).to receive(:data).and_return({system: {}})
      expect(subject).not_to receive(:do_check)

      subject.check_sensors
    end
  end

  describe 'check_smart' do
    before do
      allow(host).to receive(:system_disks).and_return(['sda', 'sdb'])
    end

    it 'should check SMART status when data is present' do
      allow(subject).to receive(:data).and_return({system: {'smart' => {'sda' => {'smart_status' => 'PASSED'}, 'sdb' => {'smart_status' => 'PASSED'}}}})
      expect(subject).to receive(:do_check).with(:smart, 'SMART', {critical: false}, message: '')

      subject.check_smart
    end

    it 'should report missing disks' do
      allow(subject).to receive(:data).and_return({system: {'smart' => {'sda' => {'smart_status' => 'PASSED'}}}})
      expect(subject).to receive(:do_check).with(:smart, 'SMART', {critical: true}, hash_including(:message))

      subject.check_smart
    end

    it 'should report failed SMART test' do
      allow(subject).to receive(:data).and_return({system: {'smart' => {'sda' => {'smart_status' => 'FAILED'}, 'sdb' => {'smart_status' => 'PASSED'}}}})
      expect(subject).to receive(:do_check).with(:smart, 'SMART', {critical: true}, hash_including(:message))

      subject.check_smart
    end
  end

  describe 'check_zpools' do
    it 'should check zpool usage when data is present' do
      allow(subject).to receive(:data).and_return({system: {'zpools' => {'tank' => {cap_percentage: '50'}}}})
      expect(subject).to receive(:do_check_value).with(:zpools_usage, 50.0, {critical: 90, warning: 75}, hash_including(:unit))

      subject.check_zpools
    end

    it 'should use max usage across pools' do
      allow(subject).to receive(:data).and_return({system: {'zpools' => {'tank' => {cap_percentage: '50'}, 'pool2' => {cap_percentage: '80'}}}})
      expect(subject).to receive(:do_check_value).with(:zpools_usage, 80.0, anything, anything)

      subject.check_zpools
    end

    it 'should do nothing when no zpool data' do
      allow(subject).to receive(:data).and_return({system: {}})
      expect(subject).not_to receive(:do_check_value)

      subject.check_zpools
    end
  end

  describe 'check' do
    it 'should call check_system_info and check md, sensors, smart, zpools' do
      expect(subject).to receive(:check_system_info).and_return true

      expect(subject).to receive(:check_md).and_return true
      expect(subject).to receive(:check_sensors).and_return true
      expect(subject).to receive(:check_smart).and_return true
      expect(subject).to receive(:check_zpools).and_return true

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