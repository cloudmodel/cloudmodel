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

  describe 'persist_cpu_count' do
    it 'should store the probed core count on the host record' do
      allow(subject).to receive(:data).and_return({system: {'cpu' => {'cpus' => '12'}}})
      allow(host).to receive(:[]).with(:cpu_count).and_return(-1)
      expect(host).to receive(:update_attribute).with(:cpu_count, 12)

      subject.persist_cpu_count
    end

    it 'should not write when the stored count is already current' do
      allow(subject).to receive(:data).and_return({system: {'cpu' => {'cpus' => '12'}}})
      allow(host).to receive(:[]).with(:cpu_count).and_return(12)
      expect(host).not_to receive(:update_attribute)

      subject.persist_cpu_count
    end

    it 'should do nothing without a usable cpu count' do
      allow(subject).to receive(:data).and_return({system: {'cpu' => {}}})
      expect(host).not_to receive(:update_attribute)

      subject.persist_cpu_count
    end
  end

  describe 'check_zpool_health' do
    it 'should alert critical when a pool is not ONLINE' do
      allow(subject).to receive(:data).and_return({system: {'zpools' => {'tank' => {health: 'ONLINE'}, 'data' => {health: 'DEGRADED'}}}})
      expect(subject).to receive(:do_check).with(:zpools_health, 'ZFS pool health', {critical: true}, hash_including(message: 'data: DEGRADED'))

      subject.check_zpool_health
    end

    it 'should be ok when all pools are ONLINE' do
      allow(subject).to receive(:data).and_return({system: {'zpools' => {'tank' => {health: 'ONLINE'}}}})
      expect(subject).to receive(:do_check).with(:zpools_health, anything, {critical: false}, anything)

      subject.check_zpool_health
    end
  end

  describe 'check_smart_trending' do
    it 'should warn with a human message when a cumulative wear counter increases' do
      subject.instance_variable_set :@prev_system, {'smart' => {'sda' => {'reallocated_sector_ct' => '12'}}}
      allow(subject).to receive(:data).and_return({system: {'smart' => {'sda' => {
        'reallocated_sector_ct' => '16', 'device_model' => 'Commodore 1541', 'serial_number' => '234552'
      }}}})
      expect(subject).to receive(:do_check).with(:smart_trending, anything, {warning: true},
        hash_including(message: a_string_including('Drive sda (Commodore 1541, S/N 234552) has a growing number of reallocated (remapped) sectors (12 → 16)')))

      subject.check_smart_trending
    end

    it 'should stay quiet for a stable non-zero counter' do
      subject.instance_variable_set :@prev_system, {'smart' => {'sda' => {'reallocated_sector_ct' => '16'}}}
      allow(subject).to receive(:data).and_return({system: {'smart' => {'sda' => {'reallocated_sector_ct' => '16'}}}})
      expect(subject).to receive(:do_check).with(:smart_trending, anything, {warning: false}, anything)

      subject.check_smart_trending
    end

    it 'should stay quiet on the first cycle without previous data' do
      allow(subject).to receive(:data).and_return({system: {'smart' => {'sda' => {'reallocated_sector_ct' => '16'}}}})
      expect(subject).to receive(:do_check).with(:smart_trending, anything, {warning: false}, anything)

      subject.check_smart_trending
    end

    it 'should not warn when a counter drops (replaced disk)' do
      subject.instance_variable_set :@prev_system, {'smart' => {'sda' => {'reallocated_sector_ct' => '16'}}}
      allow(subject).to receive(:data).and_return({system: {'smart' => {'sda' => {'reallocated_sector_ct' => '0'}}}})
      expect(subject).to receive(:do_check).with(:smart_trending, anything, {warning: false}, anything)

      subject.check_smart_trending
    end

    it 'should warn while sectors are pending, regardless of trend' do
      allow(subject).to receive(:data).and_return({system: {'smart' => {'sda' => {'current_pending_sector' => '2'}}}})
      expect(subject).to receive(:do_check).with(:smart_trending, anything, {warning: true},
        hash_including(message: a_string_including('Drive sda has 2 currently unreadable sectors')))

      subject.check_smart_trending
    end

    it 'should append the situational picture with RAID state for affected drives' do
      allow(subject).to receive(:data).and_return({system: {
        'smart' => {'sdb' => {'current_pending_sector' => '64', 'reallocated_sector_ct' => '16'}},
        'md' => {'devs' => {
          'md2' => {'status' => 'active', 'disks' => ['sda2', 'sdb2'], 'disks_status' => '[UU]'},
          'md3' => {'status' => 'active', 'disks' => ['sda3'], 'disks_status' => '[UU]'}
        }}
      }})
      expect(subject).to receive(:do_check).with(:smart_trending, anything, {warning: true},
        hash_including(message: a_string_including('sdb: reallocated_sector_ct=16, current_pending_sector=64 — RAID: md2 active [UU]')))

      subject.check_smart_trending
    end

    it 'should warn on depleted NVMe spare as an acute state' do
      allow(subject).to receive(:data).and_return({system: {'smart' => {
        'nvme0' => {'available_spare' => '5', 'available_spare_threshold' => '10', 'percentage_used' => '80'}
      }}})
      expect(subject).to receive(:do_check).with(:smart_trending, anything, {warning: true}, hash_including(:message))

      subject.check_smart_trending
    end
  end

  describe 'check_ntp' do
    it 'should warn when the clock is not synchronised' do
      allow(subject).to receive(:data).and_return({system: {'ntp' => {'NTPSynchronized' => 'no'}}})
      expect(subject).to receive(:do_check).with(:ntp_sync, anything, {warning: true}, hash_including(value: 'no'))

      subject.check_ntp
    end

    it 'should alert on a large absolute clock offset' do
      allow(subject).to receive(:data).and_return({system: {'ntp' => {'NTPSynchronized' => 'yes', 'offset' => '-2.5'}}})
      allow(subject).to receive(:do_check)
      expect(subject).to receive(:do_check_value).with(:ntp_offset, 2.5, {critical: 1.0, warning: 0.5}, hash_including(unit: 's'))

      subject.check_ntp
    end
  end

  describe 'check_net_links' do
    it 'should alert on a downed physical link that carried traffic, ignoring spare and virtual ones' do
      allow(subject).to receive(:data).and_return({system: {'net_dev' => {
        'eth0' => {'operstate' => 'up',   'rx_bytes' => '1000', 'tx_bytes' => '1000'},
        'eth1' => {'operstate' => 'down', 'rx_bytes' => '5000', 'tx_bytes' => '0'},    # was in use
        'eth2' => {'operstate' => 'down', 'rx_bytes' => '0',    'tx_bytes' => '0'},    # unused spare NIC
        'veth1' => {'operstate' => 'down', 'rx_bytes' => '9999', 'tx_bytes' => '9999'} # virtual
      }}})
      expect(subject).to receive(:do_check).with(:net_links_down, anything, {critical: true}, hash_including(message: 'eth1'))

      subject.check_net_links
    end
  end

  describe 'check_updates' do
    it 'should raise a task for a pending reboot and security updates' do
      allow(subject).to receive(:data).and_return({system: {'updates' => {'reboot_required' => '1', 'security_updates' => '3'}}})
      expect(subject).to receive(:do_check).with(:reboot_required, anything, {task: true}, anything)
      expect(subject).to receive(:do_check).with(:security_updates, anything, {task: true}, hash_including(value: '3'))

      subject.check_updates
    end
  end

  describe 'check_edac' do
    it 'should alert critical on uncorrectable ECC errors' do
      allow(subject).to receive(:data).and_return({system: {'edac' => {'ue_count' => '1', 'ce_count' => '0'}}})
      expect(subject).to receive(:do_check).with(:ecc_uncorrectable, anything, {critical: true}, hash_including(value: '1'))

      subject.check_edac
    end
  end

  describe 'check_kernel_log' do
    it 'should alert when an error signature increased since the previous cycle' do
      now = Time.now
      allow(host).to receive(:monitoring_last_check_at).and_return now
      subject.instance_variable_set :@prev_at, now - 60
      subject.instance_variable_set :@prev_system, {'kernel_log' => {'oom' => '0', 'mce' => '0', 'io_error' => '0', 'fs_error' => '0'}}
      allow(subject).to receive(:data).and_return({system: {'kernel_log' => {'oom' => '2', 'mce' => '0', 'io_error' => '0', 'fs_error' => '0'}}})

      expect(subject).to receive(:do_check).with(:kernel_oom, anything, {warning: true}, anything)
      allow(subject).to receive(:do_check).with(:kernel_mce, anything, {critical: false}, anything)
      allow(subject).to receive(:do_check).with(:kernel_fs_error, anything, {critical: false}, anything)
      allow(subject).to receive(:do_check).with(:kernel_io_error, anything, {warning: false}, anything)

      subject.check_kernel_log
    end
  end

  describe 'check_diskstats' do
    it 'should alert on high average I/O latency (await)' do
      now = Time.now
      allow(host).to receive(:monitoring_last_check_at).and_return now
      subject.instance_variable_set :@prev_at, now - 10
      subject.instance_variable_set :@prev_system, {'diskstats' => {'sda' => {
        'reads' => '0', 'writes' => '0', 'sectors_read' => '0', 'sectors_written' => '0', 'ms_reading' => '0', 'ms_writing' => '0'
      }}}
      allow(subject).to receive(:data).and_return({system: {'diskstats' => {'sda' => {
        'reads' => '100', 'writes' => '0', 'sectors_read' => '1000', 'sectors_written' => '0', 'ms_reading' => '20000', 'ms_writing' => '0'
      }}}})
      # 100 reads / 10s = 10 IOPS; 20000ms / 10s = 2000 ms/s; await = 2000/10 = 200ms
      expect(subject).to receive(:do_check_value).with(:disk_sda_await, be_within(0.1).of(200.0), {critical: 500, warning: 100}, hash_including(unit: 'ms'))

      subject.check_diskstats
    end
  end

  describe 'sample_metrics' do
    it 'should combine sysinfo metrics with zpool capacity, temperature sensors and SMART temps' do
      allow(subject).to receive(:sysinfo_sample_metrics).and_return('cpu.load_1' => 0.5)
      allow(subject).to receive(:data).and_return({system: {
        'zpools' => {'tank' => {cap_percentage: '50'}, 'data' => {cap_percentage: '80'}},
        'sensors' => {
          'core0' => {'type' => 'temp', 'input' => 45.0},
          'fan1' => {'type' => 'fan', 'input' => 1200.0}
        },
        'smart' => {
          'sda' => {'temperature_celsius' => '38', 'reallocated_sector_ct' => '16'},
          'sdb' => {'temperature_sensor_1' => '40', 'temperature_sensor_2' => '43'}
        }
      }})

      expect(subject.sample_metrics).to eq(
        'cpu.load_1' => 0.5,
        'zpool.tank.cap' => 50.0,
        'zpool.data.cap' => 80.0,
        'sensor.core0' => 45.0,
        'smart.sda.temp' => 38.0,
        'smart.sda.reallocated_sector_ct' => 16.0,
        'smart.sdb.temp' => 43.0
      )
    end

    it 'should just be the sysinfo metrics without zpool / sensor / smart data' do
      allow(subject).to receive(:sysinfo_sample_metrics).and_return('mem.usage' => 12.0)
      allow(subject).to receive(:data).and_return({system: {}})

      expect(subject.sample_metrics).to eq 'mem.usage' => 12.0
    end
  end

  describe 'smart_temperature' do
    it 'should take the max of the two sensors when both present' do
      expect(subject.smart_temperature('temperature_sensor_1' => '40', 'temperature_sensor_2' => '43')).to eq 43.0
    end

    it 'should fall back to temperature then temperature_celsius' do
      expect(subject.smart_temperature('temperature' => '41')).to eq 41.0
      expect(subject.smart_temperature('temperature_celsius' => '38')).to eq 38.0
    end

    it 'should return nil without a usable reading' do
      expect(subject.smart_temperature({})).to be_nil
      expect(subject.smart_temperature('temperature' => '0')).to be_nil
    end
  end

  describe 'check' do
    before do
      allow(host).to receive(:monitoring_last_check_result).and_return nil
      allow(host).to receive(:monitoring_last_check_at).and_return nil
    end

    it 'should call check_system_info and the individual host checks' do
      expect(subject).to receive(:check_system_info).and_return true

      %i(persist_cpu_count check_md check_sensors check_smart check_smart_trending
         check_zpools check_zpool_health check_conntrack check_net_dev check_net_links
         check_ntp check_kernel_log check_diskstats check_updates check_edac).each do |m|
        expect(subject).to receive(m)
      end

      expect(subject.check).to eq true
    end

    it 'should return false if system check fails' do
      expect(subject).to receive(:check_system_info).and_return false

      expect(subject).not_to receive(:check_md)
      expect(subject).not_to receive(:check_sensors)
      expect(subject).not_to receive(:check_smart)

      expect(subject.check).to eq false
    end

    it 'should unwrap the system level of the stored previous result for rate calculations' do
      # monitoring_last_check_result stores the whole data hash — sections live
      # under a 'system' key (string after the MongoDB round-trip). The rate
      # helpers read sections directly from @prev_system, so the snapshot must
      # unwrap that level or every cycle would look like the first one.
      allow(host).to receive(:monitoring_last_check_result).and_return('system' => {'nf_conntrack' => {'drop' => '5'}})
      allow(subject).to receive(:check_system_info).and_return false

      subject.check

      expect(subject.instance_variable_get(:@prev_system)).to eq('nf_conntrack' => {'drop' => '5'})
    end
  end
end