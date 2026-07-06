# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Mixins::SysinfoChecksMixin do
  # HostChecks includes the mixin and provides the simplest subject, so we use
  # it as the test vehicle (mirroring host_checks_spec.rb). The lxd_custom_volumes
  # branch of check_disks_usage is exercised separately through a Guest subject.
  let(:host) { double CloudModel::Host, name: 'testhost' }
  subject { CloudModel::Monitoring::HostChecks.new host, skip_header: true }

  describe 'check_cpu_usage' do
    it 'should do nothing when no cgroup_cpu data' do
      allow(subject).to receive(:data).and_return({system: {}})
      expect(subject).not_to receive(:do_check_value)

      subject.check_cpu_usage
    end

    it 'should check the 1 minute cpu usage' do
      allow(subject).to receive(:data).and_return({system: {'cgroup_cpu' => {'last_minute_percentage' => '42.5'}}})
      expect(subject).to receive(:do_check_value).with(
        :cpu_minute_usage, 42.5, {critical: 98, warning: 95}, unit: '%', name: 'CPU usage (1 Minute)'
      )

      subject.check_cpu_usage
    end

    it 'should check the 5 minutes cpu usage' do
      allow(subject).to receive(:data).and_return({system: {'cgroup_cpu' => {'last_5_minutes_percentage' => '60'}}})
      expect(subject).to receive(:do_check_value).with(
        :cpu_5_minutes_usage, 60.0, {critical: 95, warning: 80}, unit: '%', name: 'CPU usage (5 Minutes)'
      )

      subject.check_cpu_usage
    end

    it 'should check the 15 minutes cpu usage' do
      allow(subject).to receive(:data).and_return({system: {'cgroup_cpu' => {'last_15_minutes_percentage' => '12.3'}}})
      expect(subject).to receive(:do_check_value).with(
        :cpu_15_minutes_usage, 12.3, {critical: 90, warning: 70}, unit: '%', name: 'CPU usage (15 Minutes)'
      )

      subject.check_cpu_usage
    end

    it 'should check all three intervals when all are present' do
      allow(subject).to receive(:data).and_return({system: {'cgroup_cpu' => {
        'last_minute_percentage' => '10',
        'last_5_minutes_percentage' => '20',
        'last_15_minutes_percentage' => '30'
      }}})
      expect(subject).to receive(:do_check_value).with(:cpu_minute_usage, 10.0, anything, anything)
      expect(subject).to receive(:do_check_value).with(:cpu_5_minutes_usage, 20.0, anything, anything)
      expect(subject).to receive(:do_check_value).with(:cpu_15_minutes_usage, 30.0, anything, anything)

      subject.check_cpu_usage
    end
  end

  describe 'check_mem_usage' do
    it 'should do nothing when no mem data' do
      allow(subject).to receive(:data).and_return({system: {}})
      expect(subject).not_to receive(:do_check_value)

      subject.check_mem_usage
    end

    it 'should compute the memory usage percentage' do
      # 1000 total, 250 available => 75% used
      allow(subject).to receive(:data).and_return({system: {'mem' => {'mem_total' => '1000', 'mem_available' => '250'}}})
      expect(subject).to receive(:do_check_value).with(
        :mem_usage, 75.0, {critical: 95, warning: 90}, unit: '%'
      )

      subject.check_mem_usage
    end

    it 'should report high usage when little memory is available' do
      # 1000 total, 10 available => 99% used
      allow(subject).to receive(:data).and_return({system: {'mem' => {'mem_total' => '1000', 'mem_available' => '10'}}})
      expect(subject).to receive(:do_check_value).with(:mem_usage, 99.0, anything, anything)

      subject.check_mem_usage
    end
  end

  describe 'check_disks_usage' do
    it 'should do nothing when no df data' do
      allow(subject).to receive(:data).and_return({system: {}})
      expect(subject).not_to receive(:do_check_value)

      subject.check_disks_usage
    end

    it 'should check the highest disk usage' do
      allow(subject).to receive(:data).and_return({system: {'df' => {
        '/dev/sda1' => {'size' => '100', 'used' => '50', 'mountpoint' => '/'},
        '/dev/sda2' => {'size' => '100', 'used' => '90', 'mountpoint' => '/home'}
      }}})
      expect(subject).to receive(:do_check_value).with(
        :disks_usage, 90.0, {critical: 90, warning: 80}, hash_including(unit: '%')
      )

      subject.check_disks_usage
    end

    it 'should ignore loop devices' do
      allow(subject).to receive(:data).and_return({system: {'df' => {
        '/dev/loop0' => {'size' => '100', 'used' => '100', 'mountpoint' => '/snap'},
        '/dev/sda1' => {'size' => '100', 'used' => '40', 'mountpoint' => '/'}
      }}})
      expect(subject).to receive(:do_check_value).with(:disks_usage, 40.0, anything, anything)

      subject.check_disks_usage
    end

    it 'should skip disks with zero size' do
      allow(subject).to receive(:data).and_return({system: {'df' => {
        '/dev/sda0' => {'size' => '0', 'used' => '0', 'mountpoint' => '/empty'},
        '/dev/sda1' => {'size' => '200', 'used' => '50', 'mountpoint' => '/'}
      }}})
      expect(subject).to receive(:do_check_value).with(:disks_usage, 25.0, anything, anything)

      subject.check_disks_usage
    end

    it 'should build a message listing each disk usage' do
      allow(subject).to receive(:data).and_return({system: {'df' => {
        '/dev/sda1' => {'size' => '100', 'used' => '50', 'mountpoint' => '/'}
      }}})
      expect(subject).to receive(:do_check_value).with(
        :disks_usage, 50.0, anything, hash_including(message: "/dev/sda1: 50.00%\n")
      )

      subject.check_disks_usage
    end

    context 'on a guest with custom volumes' do
      let(:guest_host) { double CloudModel::Host, name: 'testhost' }
      let(:volume) { double CloudModel::LxdCustomVolume, mount_point: 'data', disk_space: 1024 * 200 }
      let(:guest) { double CloudModel::Guest, host: guest_host }
      subject { CloudModel::Monitoring::GuestChecks.new guest, skip_header: true }

      before do
        allow(guest).to receive(:is_a?) { |klass| klass == CloudModel::Guest }
        allow(guest).to receive(:lxd_custom_volumes).and_return([volume])
      end

      it 'should use the custom volume disk space as the size for its mountpoint' do
        # volume disk_space is 1024*200 bytes => size = disk_space/1024 = 200 (KiB)
        # used 100 / 200 => 50%
        allow(subject).to receive(:data).and_return({system: {'df' => {
          '/dev/sda1' => {'size' => '99999', 'used' => '100', 'mountpoint' => '/data'}
        }}})
        expect(subject).to receive(:do_check_value).with(:disks_usage, 50.0, anything, anything)

        subject.check_disks_usage
      end
    end
  end

  describe 'sysinfo_sample_metrics' do
    it 'should be empty without system data' do
      allow(subject).to receive(:data).and_return({system: nil})
      expect(subject.sysinfo_sample_metrics).to eq({})
    end

    it 'should extract cpu load and usage' do
      allow(subject).to receive(:data).and_return({system: {
        'cpu' => {'last_minute_load' => '0.4', 'last_5_minutes_load' => '0.5', 'last_15_minutes_load' => '0.6'},
        'cgroup_cpu' => {'last_minute_percentage' => '42', 'last_5_minutes_percentage' => '30', 'last_15_minutes_percentage' => '20'}
      }})
      metrics = subject.sysinfo_sample_metrics
      expect(metrics).to include('cpu.load_1' => 0.4, 'cpu.load_5' => 0.5, 'cpu.load_15' => 0.6)
      expect(metrics).to include('cpu.usage_1' => 42.0, 'cpu.usage_5' => 30.0, 'cpu.usage_15' => 20.0)
    end

    it 'should compute memory usage percentage' do
      allow(subject).to receive(:data).and_return({system: {'mem' => {'mem_total' => '1000', 'mem_available' => '250'}}})
      expect(subject.sysinfo_sample_metrics).to eq 'mem.usage' => 75.0
    end

    it 'should compute per-mount disk usage and skip loop / zero-size devices' do
      allow(subject).to receive(:data).and_return({system: {'df' => {
        '/dev/sda1' => {'size' => '100', 'used' => '40', 'mountpoint' => '/'},
        '/dev/loop0' => {'size' => '100', 'used' => '100', 'mountpoint' => '/snap'},
        '/dev/sda9' => {'size' => '0', 'used' => '0', 'mountpoint' => '/empty'}
      }}})
      expect(subject.sysinfo_sample_metrics).to eq 'disk./.usage' => 40.0
    end
  end

  describe 'check_swap_usage' do
    it 'should do nothing when no swap is configured' do
      allow(subject).to receive(:data).and_return({system: {'mem' => {'swap_total' => '0', 'swap_free' => '0'}}})
      expect(subject).not_to receive(:do_check_value)

      subject.check_swap_usage
    end

    it 'should check swap usage' do
      allow(subject).to receive(:data).and_return({system: {'mem' => {'swap_total' => '1000', 'swap_free' => '250'}}})
      expect(subject).to receive(:do_check_value).with(:swap_usage, 75.0, {critical: 90, warning: 75}, hash_including(unit: '%'))

      subject.check_swap_usage
    end
  end

  describe 'check_load' do
    it 'should check the 15m load normalised per core' do
      allow(subject).to receive(:data).and_return({system: {'cpu' => {'last_15_minutes_load' => '8.0', 'cpus' => '4'}}})
      expect(subject).to receive(:do_check_value).with(:load_per_core, 2.0, {critical: 4.0, warning: 2.0}, hash_including(:message))

      subject.check_load
    end

    it 'should do nothing without cpu count' do
      allow(subject).to receive(:data).and_return({system: {'cpu' => {'cpus' => '0'}}})
      expect(subject).not_to receive(:do_check_value)

      subject.check_load
    end
  end

  describe 'check_inodes_usage' do
    it 'should flag the highest inode usage across mounts' do
      allow(subject).to receive(:data).and_return({system: {'df_inodes' => {
        '/dev/sda1' => {'size' => '1000', 'used' => '900', 'mountpoint' => '/'},
        '/dev/sdb1' => {'size' => '1000', 'used' => '100', 'mountpoint' => '/data'}
      }}})
      expect(subject).to receive(:do_check_value).with(:inodes_usage, 90.0, {critical: 90, warning: 80}, hash_including(unit: '%'))

      subject.check_inodes_usage
    end
  end

  describe 'check_systemd_units' do
    it 'should warn when a unit has failed' do
      allow(subject).to receive(:data).and_return({system: {'systemd' => {
        'ssh.service' => {'active' => 'active', 'sub' => 'running'},
        'broken.service' => {'active' => 'failed', 'sub' => 'failed'}
      }}})
      expect(subject).to receive(:do_check).with(:systemd_failed, anything, {warning: true}, hash_including(message: 'broken.service'))

      subject.check_systemd_units
    end
  end

  describe 'check_readonly_fs' do
    it 'should alert critical on a writable filesystem mounted read-only' do
      allow(subject).to receive(:data).and_return({system: {'mounts' => {
        '/dev/sda1' => {'mountpoint' => '/', 'format' => 'ext4', 'params' => 'ro,relatime'},
        '/dev/sda2' => {'mountpoint' => '/home', 'format' => 'ext4', 'params' => 'rw,relatime'},
        'squash' => {'mountpoint' => '/snap', 'format' => 'squashfs', 'params' => 'ro'}
      }}})
      expect(subject).to receive(:do_check).with(:readonly_fs, anything, {critical: true}, hash_including(message: '/ (ext4)'))

      subject.check_readonly_fs
    end
  end

  describe 'sysinfo_sample_metrics mount filter' do
    it 'should skip virtual filesystems and LXD container mounts in disk samples' do
      allow(subject).to receive(:data).and_return({system: {'df' => {
        '/dev/sda1' => {'mountpoint' => '/', 'size' => '1000', 'used' => '500'},
        'zpool1' => {'mountpoint' => '/var/lib/lxd/storage-pools/default/containers/web01-1', 'size' => '1000', 'used' => '500'},
        'tmpfs/run' => {'mountpoint' => '/run', 'size' => '1000', 'used' => '500'},
        'tmpfs/sys' => {'mountpoint' => '/sys/fs/cgroup', 'size' => '1000', 'used' => '500'},
        'snap' => {'mountpoint' => '/var/snap/lxd/common/ns', 'size' => '1000', 'used' => '500'},
        '/dev/sdb1' => {'mountpoint' => '/cloud', 'size' => '1000', 'used' => '500'}
      }}})

      metrics = subject.sysinfo_sample_metrics
      expect(metrics.keys.select { |k| k.start_with?('disk.') }.sort).to eq ['disk./.usage', 'disk./cloud.usage']
    end
  end

  describe 'check_cgroup_limits' do
    it 'should alert on PID usage ratio' do
      allow(subject).to receive(:data).and_return({system: {'cgroup_limits' => {'pids_current' => '180', 'pids_max' => '200'}}})
      expect(subject).to receive(:do_check_value).with(:cgroup_pids, 90.0, {critical: 90, warning: 80}, hash_including(unit: '%'))

      subject.check_cgroup_limits
    end

    it 'should skip PID check when pids_max is unlimited' do
      allow(subject).to receive(:data).and_return({system: {'cgroup_limits' => {'pids_current' => '180', 'pids_max' => 'max'}}})
      expect(subject).not_to receive(:do_check_value)

      subject.check_cgroup_limits
    end

    it 'should warn on in-container OOM kills but only graph memory/CPU pressure' do
      now = Time.now
      allow(host).to receive(:monitoring_last_check_at).and_return now
      subject.instance_variable_set :@prev_at, now - 60
      subject.instance_variable_set :@prev_system, {'cgroup_limits' => {'mem_hits' => '0', 'cpu_nr_throttled' => '0', 'oom_kills' => '0'}}
      allow(subject).to receive(:data).and_return({system: {'cgroup_limits' => {'mem_hits' => '30', 'cpu_nr_throttled' => '6', 'oom_kills' => '2'}}})

      expect(subject).to receive(:do_check).with(:cgroup_oom, anything, {warning: true}, anything)
      expect(subject).not_to receive(:do_check).with(:cgroup_mem_pressure, anything, anything, anything)
      expect(subject).not_to receive(:do_check).with(:cgroup_cpu_throttled, anything, anything, anything)

      subject.check_cgroup_limits
    end
  end

  describe 'check_system_info' do
    it 'should run all sysinfo checks when system info is available' do
      allow(subject).to receive(:data).and_return({system: {'error' => ''}})
      expect(subject).to receive(:do_check).with(
        :sys_info_available, 'Check system information', {fatal: false}, message: ''
      ).and_return true

      expect(subject).to receive(:check_cpu_usage)
      expect(subject).to receive(:check_mem_usage)
      expect(subject).to receive(:check_swap_usage)
      expect(subject).to receive(:check_load)
      expect(subject).to receive(:check_disks_usage)
      expect(subject).to receive(:check_inodes_usage)
      expect(subject).to receive(:check_systemd_units)
      expect(subject).to receive(:check_readonly_fs)
      expect(subject).to receive(:check_cgroup_limits)

      expect(subject.check_system_info).to eq true
    end

    it 'should flag a fatal issue and skip sub checks when system info has an error' do
      allow(subject).to receive(:data).and_return({system: {'error' => 'boom'}})
      expect(subject).to receive(:do_check).with(
        :sys_info_available, 'Check system information', {fatal: true}, message: 'boom'
      ).and_return false

      expect(subject).not_to receive(:check_cpu_usage)
      expect(subject).not_to receive(:check_mem_usage)
      expect(subject).not_to receive(:check_disks_usage)

      expect(subject.check_system_info).to eq nil
    end
  end
end
