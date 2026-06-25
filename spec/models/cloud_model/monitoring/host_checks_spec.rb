# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::HostChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  subject { CloudModel::Monitoring::HostChecks.new host, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe 'self.check' do
    it 'should skip hosts that are booting or not_started' do
      booting = double CloudModel::Host, name: 'booting', deploy_state: :booting
      not_started = double CloudModel::Host, name: 'not_started', deploy_state: :not_started
      allow(CloudModel::Host).to receive(:scoped).and_return [booting, not_started]

      expect(CloudModel::Monitoring::HostChecks).not_to receive(:new)
      expect(CloudModel::Monitoring::HostChecks).not_to receive(:handle_cloudmodel_monitoring_exception)

      expect { CloudModel::Monitoring::HostChecks.check }.to output('').to_stdout
    end

    it 'should run host, guest, volume and service checks for active hosts' do
      volume = double CloudModel::LxdCustomVolume
      service = double CloudModel::Services::Base
      guest = double CloudModel::Guest, lxd_custom_volumes: [volume], services: [service]
      active_host = double CloudModel::Host, name: 'active', deploy_state: :running, guests: [guest]
      allow(CloudModel::Host).to receive(:scoped).and_return [active_host]

      host_checks = double 'HostChecks', check: true
      guest_checks = double 'GuestChecks', check: true
      volume_checks = double 'LxdCustomVolumeChecks', check: true
      service_checks = double 'ServiceChecks', check: true

      expect(CloudModel::Monitoring::HostChecks).to receive(:new).with(active_host).and_return host_checks
      expect(CloudModel::Monitoring::GuestChecks).to receive(:new).with(guest).and_return guest_checks
      expect(CloudModel::Monitoring::LxdCustomVolumeChecks).to receive(:new).with(volume).and_return volume_checks
      expect(CloudModel::Monitoring::ServiceChecks).to receive(:new).with(service).and_return service_checks

      # Run the work inline instead of spawning real threads/executors, so the
      # stubbed mocks below are not touched from another thread (RSpec mocks are
      # not thread-safe).
      allow(Thread).to receive(:new) { |&blk| double('Thread', join: blk.call) }
      allow(Rails.application.executor).to receive(:wrap).and_yield
      allow(CloudModel::Monitoring::HostChecks).to receive(:handle_cloudmodel_monitoring_exception) do |*args, &blk|
        blk.call
      end

      expect { CloudModel::Monitoring::HostChecks.check }.to output(/Threading/).to_stdout

      expect(host_checks).to have_received(:check)
      expect(guest_checks).to have_received(:check)
      expect(volume_checks).to have_received(:check)
      expect(service_checks).to have_received(:check)
    end

    it 'should skip guest sub-checks when the host check fails' do
      guest = double CloudModel::Guest
      active_host = double CloudModel::Host, name: 'active', deploy_state: :running, guests: [guest]
      allow(CloudModel::Host).to receive(:scoped).and_return [active_host]

      host_checks = double 'HostChecks', check: false
      expect(CloudModel::Monitoring::HostChecks).to receive(:new).with(active_host).and_return host_checks
      expect(CloudModel::Monitoring::GuestChecks).not_to receive(:new)

      allow(Thread).to receive(:new) { |&blk| double('Thread', join: blk.call) }
      allow(Rails.application.executor).to receive(:wrap).and_yield
      allow(CloudModel::Monitoring::HostChecks).to receive(:handle_cloudmodel_monitoring_exception) do |*args, &blk|
        blk.call
      end

      expect { CloudModel::Monitoring::HostChecks.check }.to output(/Done/).to_stdout
    end
  end

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

    it 'should fall back to a zero usage with an empty message when there are no pools' do
      allow(subject).to receive(:data).and_return({system: {'zpools' => {}}})
      expect(subject).to receive(:do_check_value).with(:zpools_usage, 0, {critical: 90, warning: 75}, hash_including(unit: '%', message: ''))

      subject.check_zpools
    end
  end

  describe 'sample_metrics' do
    it 'should combine sysinfo metrics with zpool capacity and temperature sensors' do
      allow(subject).to receive(:sysinfo_sample_metrics).and_return('cpu.load_1' => 0.5)
      allow(subject).to receive(:data).and_return({system: {
        'zpools' => {'tank' => {cap_percentage: '50'}, 'data' => {cap_percentage: '80'}},
        'sensors' => {
          'core0' => {'type' => 'temp', 'input' => 45.0},
          'fan1' => {'type' => 'fan', 'input' => 1200.0}
        }
      }})

      expect(subject.sample_metrics).to eq(
        'cpu.load_1' => 0.5,
        'zpool.tank.cap' => 50.0,
        'zpool.data.cap' => 80.0,
        'sensor.core0' => 45.0
      )
    end

    it 'should just be the sysinfo metrics without zpool / sensor data' do
      allow(subject).to receive(:sysinfo_sample_metrics).and_return('mem.usage' => 12.0)
      allow(subject).to receive(:data).and_return({system: {}})

      expect(subject.sample_metrics).to eq 'mem.usage' => 12.0
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