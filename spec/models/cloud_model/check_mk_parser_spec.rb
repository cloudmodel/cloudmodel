# encoding: UTF-8

require 'spec_helper'

describe CloudModel::CheckMkParser do
  describe '.parse' do
    it 'should parse check_mk section' do
      result = CloudModel::CheckMkParser.parse "<<<check_mk>>>\nVersion: 2.2.0\nAgentOS: linux\n"
      expect(result['check_mk']['version']).to eq '2.2.0'
      expect(result['check_mk']['agent_os']).to eq 'linux'
    end

    it 'should parse mem section' do
      result = CloudModel::CheckMkParser.parse "<<<mem>>>\nMemTotal: 8192 kB\nMemFree: 4096 kB\n"
      expect(result['mem']['mem_total']).to eq '8192 kB'
      expect(result['mem']['mem_free']).to eq '4096 kB'
    end

    it 'should parse df section' do
      result = CloudModel::CheckMkParser.parse "<<<df>>>\n/dev/sda1 ext4 100000 50000 45000 53% /\n"
      expect(result['df']['/dev/sda1']['mountpoint']).to eq '/'
      expect(result['df']['/dev/sda1']['used']).to eq '50000'
    end

    it 'should rename df_v2 to df' do
      result = CloudModel::CheckMkParser.parse "<<<df_v2>>>\n/dev/sda1 ext4 100000 50000 45000 53% /\n"
      expect(result['df']).not_to be_nil
      expect(result['df_v2']).to be_nil
    end

    it 'should parse cpu section' do
      result = CloudModel::CheckMkParser.parse "<<<cpu>>>\n0.5 1.0 1.5 1/200 12345 4\n"
      expect(result['cpu']['cpus']).to eq '4'
      expect(result['cpu']['last_minute_load']).to eq '0.5'
    end

    it 'should parse mounts section' do
      result = CloudModel::CheckMkParser.parse "<<<mounts>>>\n/dev/sda1 / ext4 rw,relatime 0 0\n"
      expect(result['mounts']['/dev/sda1']['mountpoint']).to eq '/'
      expect(result['mounts']['/dev/sda1']['format']).to eq 'ext4'
    end

    it 'should parse zpools section' do
      result = CloudModel::CheckMkParser.parse "<<<zpools>>>\ntank\t10G\t5G\t5G\t-\t10%\t50%\t1.00x\tONLINE\t-\n"
      expect(result['zpools']['tank'][:health]).to eq 'ONLINE'
      expect(result['zpools']['tank'][:cap_percentage]).to eq '50%'
    end

    it 'should parse zpools with the 11-column CKPOINT layout of ZFS >= 0.8' do
      # Old plugin without a pinned column list on a newer host: CKPOINT ('-')
      # is inserted after FREE and must not shift health onto the dedup column.
      result = CloudModel::CheckMkParser.parse "<<<zpools>>>\nguests\t10G\t3G\t7G\t-\t-\t10\t28\t1.00\tONLINE\t-\n"
      expect(result['zpools']['guests'][:health]).to eq 'ONLINE'
      expect(result['zpools']['guests'][:cap_percentage]).to eq '28'
      expect(result['zpools']['guests'][:dedup]).to eq '1.00'
    end

    it 'should parse multiple sections' do
      input = "<<<check_mk>>>\nVersion: 2.2.0\n<<<mem>>>\nMemTotal: 8192 kB\n"
      result = CloudModel::CheckMkParser.parse input
      expect(result['check_mk']).not_to be_nil
      expect(result['mem']).not_to be_nil
    end

    it 'should store unknown sections as data' do
      result = CloudModel::CheckMkParser.parse "<<<cgroup_cpu>>>\nsome raw data\n"
      expect(result['cgroup_cpu']['data']).to eq "some raw data\n"
    end

    it 'should handle empty input' do
      expect(CloudModel::CheckMkParser.parse('')).to eq({})
    end

    it 'should keep colon keys in mem section value' do
      result = CloudModel::CheckMkParser.parse "<<<mem>>>\nCommitted_AS: 1234 kB\nSwapTotal: 0 kB\n"
      expect(result['mem']['committed_as']).to eq '1234 kB'
      expect(result['mem']['swap_total']).to eq '0 kB'
    end

    describe 'df section' do
      it 'should rename tmpfs key to include mountpoint' do
        result = CloudModel::CheckMkParser.parse "<<<df>>>\ntmpfs tmpfs 1000 100 900 10% /run\n"
        expect(result['df']['tmpfs/run']).not_to be_nil
        expect(result['df']['tmpfs/run']['mountpoint']).to eq '/run'
        expect(result['df']['tmpfs/run']['type']).to eq 'tmpfs'
      end

      it 'should toggle off parsing inside df_inodes block' do
        input = "<<<df>>>\n/dev/sda1 ext4 100000 50000 45000 53% /\n" \
                "[df_inodes_start]\n/dev/sda1 ext4 9999 9999 9999 99% /\n[df_inodes_end]\n" \
                "/dev/sdb1 ext4 200000 100000 90000 53% /data\n"
        result = CloudModel::CheckMkParser.parse input
        # the inodes line must not overwrite the real df data
        expect(result['df']['/dev/sda1']['used']).to eq '50000'
        expect(result['df']['/dev/sdb1']['mountpoint']).to eq '/data'
      end

      it 'should toggle off parsing inside df_lsblk block' do
        input = "<<<df>>>\n/dev/sda1 ext4 100000 50000 45000 53% /\n" \
                "[df_lsblk_start]\nignored garbage line here ok\n[df_lsblk_end]\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['df']['/dev/sda1']['used']).to eq '50000'
        expect(result['df']['ignored']).to be_nil
      end
    end

    it 'should skip cpu lines without a second field' do
      result = CloudModel::CheckMkParser.parse "<<<cpu>>>\nonlyonefield\n"
      expect(result['cpu']['last_minute_load']).to be_nil
    end

    it 'should parse lxc_container_cpu section' do
      result = CloudModel::CheckMkParser.parse "<<<lxc_container_cpu>>>\nnum_cpus 4\n"
      expect(result['lxc_container_cpu']['num_cpus']).to eq '4'
    end

    describe 'md section' do
      it 'should parse personalities and devices' do
        input = "<<<md>>>\n" \
                "Personalities : [raid1] [raid0]\n" \
                "md0 : active raid1 sda1[0] sdb1[1]\n" \
                "      976630336 blocks super 1.2 [2/2] [UU]\n" \
                "unused devices: <none>\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['md']['personalities']).to eq ['[raid1]', '[raid0]']
        expect(result['md']['unused_devices']).to eq '<none>'
        expect(result['md']['devs']['md0']['status']).to eq 'active'
        expect(result['md']['devs']['md0']['raid_level']).to eq 'raid1'
        expect(result['md']['devs']['md0']['disks']).to eq ['sda1', 'sdb1']
        expect(result['md']['devs']['md0']['blocks']).to eq '976630336'
        expect(result['md']['devs']['md0']['disks_status']).to eq '[UU]'
      end

      it 'should ignore blank-key lines' do
        input = "<<<md>>>\n" \
                "md0 : active raid1 sda1[0] sdb1[1]\n" \
                "  : \n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['md']['devs']['md0']['status']).to eq 'active'
      end

      it 'should store an unrecognised continuation line as line2' do
        input = "<<<md>>>\n" \
                "md0 : active raid1 sda1[0] sdb1[1]\n" \
                "      resync=DELAYED\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['md']['devs']['md0'][:line2]).to eq 'resync=DELAYED'
      end

      it 'should parse status note in parentheses' do
        input = "<<<md>>>\n" \
                "md0 : active (auto-read-only) raid1 sda1[0] sdb1[1]\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['md']['devs']['md0']['status_note']).to eq 'auto-read-only'
        expect(result['md']['devs']['md0']['raid_level']).to eq 'raid1'
      end
    end

    describe 'smart section' do
      it 'should parse device blocks and attributes' do
        input = "<<<smart>>>\n" \
                "[/dev/sda]\n" \
                "Device Model: Commodore 1541\n" \
                "Reallocated_Sector_Ct: 0 some extra\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['smart']['sda']['device_model']).to eq 'Commodore 1541'
        expect(result['smart']['sda']['reallocated_sector_ct']).to eq '0'
      end

      it 'should use dash when value missing' do
        input = "<<<smart>>>\n[/dev/sdb]\nSomeKeyOnly\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['smart']['sdb']['some_key_only']).to eq '-'
      end
    end

    describe 'sensors section' do
      it 'should parse adapters and sensor values' do
        # A blank line resets the adapter; the next non-empty line becomes the
        # new adapter. The current sensor is flushed when a new sensor starts or
        # when the section ends, so a trailing section flushes the last sensor.
        input = "<<<sensors>>>\n" \
                "coretemp-isa-0000\n" \
                "Adapter: ISA adapter\n" \
                "Core 0:\n" \
                "  temp1_input: 45.0\n" \
                "  temp1_max: 100.0\n" \
                "\n" \
                "nct6775-isa-0290\n" \
                "fan1:\n" \
                "  fan1_input: 1200.0\n" \
                "<<<mem>>>\nMemTotal: 1 kB\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['sensors']['core_0']['adapter']).to eq 'coretemp-isa-0000'
        expect(result['sensors']['core_0']['type']).to eq 'temp'
        expect(result['sensors']['core_0']['input']).to eq 45.0
        expect(result['sensors']['core_0']['max']).to eq 100.0
        expect(result['sensors']['fan1']['adapter']).to eq 'nct6775-isa-0290'
        expect(result['sensors']['fan1']['input']).to eq 1200.0
      end

      it 'should flush last sensor on section change' do
        input = "<<<sensors>>>\n" \
                "coretemp-isa-0000\n" \
                "Core 0:\n" \
                "  temp1_input: 50.0\n" \
                "<<<mem>>>\nMemTotal: 1 kB\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['sensors']['core_0']['input']).to eq 50.0
      end
    end

    describe 'nf_conntrack section' do
      it 'should parse count and max' do
        result = CloudModel::CheckMkParser.parse "<<<nf_conntrack>>>\ncount 12345\nmax 262144\n"
        expect(result['nf_conntrack']['count']).to eq '12345'
        expect(result['nf_conntrack']['max']).to eq '262144'
      end

      it 'should sum per-CPU hex stat counters by column name' do
        input = "<<<nf_conntrack>>>\ncount 10\nmax 100\n[stat]\n" \
                "entries found invalid insert_failed drop early_drop search_restart\n" \
                "0000000a 00000000 00000000 00000002 00000001 00000000 00000000\n" \
                "0000000a 00000000 00000000 00000003 00000000 00000000 00000000\n"
        result = CloudModel::CheckMkParser.parse input
        # insert_failed = 0x2 + 0x3 = 5, drop = 0x1 + 0x0 = 1
        expect(result['nf_conntrack']['insert_failed']).to eq 5
        expect(result['nf_conntrack']['drop']).to eq 1
        # `entries` is the global size repeated per CPU and must not be summed
        expect(result['nf_conntrack']['entries']).to be_nil
        expect(result['nf_conntrack']['count']).to eq '10'
      end
    end

    describe 'net_dev section' do
      it 'should parse per-interface counters and skip header lines' do
        input = "<<<net_dev>>>\n" \
                "Inter-|   Receive                                                |  Transmit\n" \
                " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n" \
                "    lo:  158 2 0 0 0 0 0 0  158 2 0 0 0 0 0 0\n" \
                "  eth0: 1000 10 1 2 0 0 0 0  2000 20 3 4 0 0 0 0\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['net_dev']['Inter-|   Receive']).to be_nil
        expect(result['net_dev']['eth0']['rx_bytes']).to eq '1000'
        expect(result['net_dev']['eth0']['rx_packets']).to eq '10'
        expect(result['net_dev']['eth0']['rx_errs']).to eq '1'
        expect(result['net_dev']['eth0']['rx_drop']).to eq '2'
        expect(result['net_dev']['eth0']['tx_bytes']).to eq '2000'
        expect(result['net_dev']['eth0']['tx_errs']).to eq '3'
        expect(result['net_dev']['lo']['rx_bytes']).to eq '158'
      end

      it 'should handle a byte count that touches the colon-less name field' do
        # When rx_bytes is huge the name and value run together after the colon
        input = "<<<net_dev>>>\n" \
                "  eth0:12345678901 100 0 0 0 0 0 0 500 50 0 0 0 0 0 0\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['net_dev']['eth0']['rx_bytes']).to eq '12345678901'
        expect(result['net_dev']['eth0']['rx_packets']).to eq '100'
      end
    end

    describe 'net_dev link block' do
      it 'should merge operstate and speed into the interface' do
        input = "<<<net_dev>>>\n" \
                "  eth0: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n" \
                "[link]\n" \
                "eth0 up 1000\n" \
                "lxdbr0 down unknown\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['net_dev']['eth0']['operstate']).to eq 'up'
        expect(result['net_dev']['eth0']['speed']).to eq '1000'
        expect(result['net_dev']['eth0']['rx_bytes']).to eq '1000'
        expect(result['net_dev']['lxdbr0']['operstate']).to eq 'down'
      end
    end

    describe 'df_check_mk section (renamed stock df)' do
      it 'should populate df_inodes from the renamed section' do
        input = "<<<df_check_mk>>>\n" \
                "/dev/sda1 ext4 100000 50000 45000 53% /\n" \
                "[df_inodes_start]\n" \
                "/dev/sda1 ext4 1000 900 100 90% /\n" \
                "[df_inodes_end]\n" \
                "<<<df>>>\n" \
                "/dev/sda1 ext4 100000 50000 45000 53% /\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['df_inodes']['/dev/sda1']['used']).to eq '900'
        expect(result['df_inodes']['/dev/sda1']['mountpoint']).to eq '/'
        # the appended plain df section stays the canonical byte usage
        expect(result['df']['/dev/sda1']['used']).to eq '50000'
      end
    end

    describe 'df inodes block' do
      it 'should store inode counts separately from df bytes' do
        input = "<<<df>>>\n" \
                "/dev/sda1 ext4 100000 50000 45000 53% /\n" \
                "[df_inodes_start]\n" \
                "/dev/sda1 ext4 1000 900 100 90% /\n" \
                "[df_inodes_end]\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['df']['/dev/sda1']['used']).to eq '50000'
        expect(result['df_inodes']['/dev/sda1']['used']).to eq '900'
        expect(result['df_inodes']['/dev/sda1']['size']).to eq '1000'
        expect(result['df_inodes']['/dev/sda1']['mountpoint']).to eq '/'
      end
    end

    it 'should parse ntp section' do
      result = CloudModel::CheckMkParser.parse "<<<ntp>>>\nNTP yes\nNTPSynchronized yes\noffset -0.000123\n"
      expect(result['ntp']['NTPSynchronized']).to eq 'yes'
      expect(result['ntp']['offset']).to eq '-0.000123'
    end

    it 'should parse kernel_log section' do
      result = CloudModel::CheckMkParser.parse "<<<kernel_log>>>\noom 2\nmce 0\nio_error 1\nfs_error 0\n"
      expect(result['kernel_log']['oom']).to eq '2'
      expect(result['kernel_log']['fs_error']).to eq '0'
    end

    it 'should parse updates section' do
      result = CloudModel::CheckMkParser.parse "<<<updates>>>\nreboot_required 1\nupdates 5\nsecurity_updates 3\n"
      expect(result['updates']['reboot_required']).to eq '1'
      expect(result['updates']['security_updates']).to eq '3'
    end

    it 'should parse versions section (value keeps spaces)' do
      result = CloudModel::CheckMkParser.parse "<<<versions>>>\nos_id debian\nos_version 12\nos_pretty Debian GNU/Linux 12 (bookworm)\nkernel 6.1.0-cloud-amd64\narch x86_64\nzfs 2.1.11-1\nlxd 5.0.2\n"
      expect(result['versions']['os_id']).to eq 'debian'
      expect(result['versions']['os_version']).to eq '12'
      expect(result['versions']['os_pretty']).to eq 'Debian GNU/Linux 12 (bookworm)'
      expect(result['versions']['kernel']).to eq '6.1.0-cloud-amd64'
      expect(result['versions']['zfs']).to eq '2.1.11-1'
      expect(result['versions']['lxd']).to eq '5.0.2'
    end

    it 'should parse packages section into name => version/arch' do
      result = CloudModel::CheckMkParser.parse "<<<packages>>>\nbash\t5.2.15-2\tamd64\nzfsutils-linux\t2.1.11-1\tamd64\n"
      expect(result['packages']['bash']).to eq({'version' => '5.2.15-2', 'arch' => 'amd64'})
      expect(result['packages']['zfsutils-linux']['version']).to eq '2.1.11-1'
    end

    it 'should parse a cached packages section (strips the :cached annotation)' do
      result = CloudModel::CheckMkParser.parse "<<<packages:cached(1700000000,3600)>>>\nbash\t5.2.15-2\tamd64\n"
      expect(result['packages']['bash']['version']).to eq '5.2.15-2'
    end

    it 'should parse edac section' do
      result = CloudModel::CheckMkParser.parse "<<<edac>>>\nce_count 4\nue_count 0\n"
      expect(result['edac']['ce_count']).to eq '4'
      expect(result['edac']['ue_count']).to eq '0'
    end

    it 'should parse cgroup_limits section' do
      result = CloudModel::CheckMkParser.parse "<<<cgroup_limits>>>\nmem_hits 12\noom_kills 0\npids_current 40\npids_max 200\ncpu_nr_throttled 5\n"
      expect(result['cgroup_limits']['mem_hits']).to eq '12'
      expect(result['cgroup_limits']['pids_current']).to eq '40'
      expect(result['cgroup_limits']['pids_max']).to eq '200'
      expect(result['cgroup_limits']['cpu_nr_throttled']).to eq '5'
    end

    it 'should parse diskstats section for whole disks' do
      input = "<<<diskstats>>>\n" \
              "   8       0 sda 1000 0 20000 500 2000 0 40000 800 0 300 1300\n" \
              "   8       1 sda1 10 0 20 5 20 0 40 8 0 3 13\n"
      result = CloudModel::CheckMkParser.parse input
      expect(result['diskstats']['sda']['sectors_read']).to eq '20000'
      expect(result['diskstats']['sda']['ms_reading']).to eq '500'
      expect(result['diskstats']['sda']['writes']).to eq '2000'
      expect(result['diskstats']['sda1']['reads']).to eq '10'
    end

    it 'should parse systemd section' do
      input = "<<<systemd>>>\nssh.service loaded active running OpenSSH server daemon\n"
      result = CloudModel::CheckMkParser.parse input
      expect(result['systemd']['ssh.service']['load']).to eq 'loaded'
      expect(result['systemd']['ssh.service']['active']).to eq 'active'
      expect(result['systemd']['ssh.service']['sub']).to eq 'running'
      expect(result['systemd']['ssh.service']['description']).to eq 'OpenSSH server daemon'
    end

    describe 'systemd_units section' do
      it 'should parse list-unit-files block' do
        input = "<<<systemd_units>>>\n" \
                "[list-unit-files]\n" \
                "ssh.service enabled enabled\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['systemd_units']['ssh.service']['state']).to eq 'enabled'
        expect(result['systemd_units']['ssh.service']['preset']).to eq 'enabled'
      end

      it 'should parse all block' do
        input = "<<<systemd_units>>>\n" \
                "[all]\n" \
                "ssh.service loaded active running OpenSSH server daemon\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['systemd_units']['ssh.service']['load']).to eq 'loaded'
        expect(result['systemd_units']['ssh.service']['active']).to eq 'active'
        expect(result['systemd_units']['ssh.service']['sub']).to eq 'running'
        expect(result['systemd_units']['ssh.service']['description']).to eq 'OpenSSH server daemon'
      end

      it 'should accumulate status block lines' do
        # _systemd_unit starts as '' (truthy), so the unit name is never
        # extracted from the status header and all lines collect under key ''.
        input = "<<<systemd_units>>>\n" \
                "[status]\n" \
                "* ssh.service - OpenSSH\n" \
                "   Active: active (running)\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['systemd_units']['']['status']).to include 'Active: active (running)'
        expect(result['systemd_units']['']['status']).to include 'ssh.service'
      end

      it 'should keep UTF-8 bullets intact and strip ANSI escapes in status lines' do
        input = "<<<systemd_units>>>\n" \
                "[status]\n" \
                "\e[0;1;32m●\e[0m ssh.service - OpenSSH\n" \
                "   Active: active (running)\n"
        result = CloudModel::CheckMkParser.parse input.dup.force_encoding('ASCII-8BIT')
        expect(result['systemd_units']['']['status']).to include '● ssh.service'
        expect(result['systemd_units']['']['status']).not_to include "\e["
        expect(result['systemd_units']['']['status']).not_to include "�"
      end
    end

    it 'should parse lxd section as yaml and unroll config' do
      input = "<<<lxd>>>\n" \
              "- name: web01\n" \
              "  config:\n" \
              "    image.os: ubuntu\n" \
              "    image.release: jammy\n" \
              "  expanded_config:\n" \
              "    limits.cpu: \"4\"\n" \
              "<<<mem>>>\nMemTotal: 1 kB\n"
      result = CloudModel::CheckMkParser.parse input
      expect(result['lxd'].first['name']).to eq 'web01'
      expect(result['lxd'].first['config']['image']['os']).to eq 'ubuntu'
      expect(result['lxd'].first['expanded_config']['limits']['cpu']).to eq '4'
    end

    it 'should merge a nested container key into the lxd entry' do
      input = "<<<lxd>>>\n" \
              "- container:\n" \
              "    name: web02\n" \
              "    config: {}\n" \
              "    expanded_config: {}\n" \
              "<<<mem>>>\nMemTotal: 1 kB\n"
      result = CloudModel::CheckMkParser.parse input
      expect(result['lxd'].first['name']).to eq 'web02'
      expect(result['lxd'].first).not_to have_key('container')
    end

    it 'should split colon-suffixed context into data_ keys' do
      input = "<<<plugin:sep0:cached(123,456)>>>\nraw payload\n"
      result = CloudModel::CheckMkParser.parse input
      expect(result['plugin']['data_sep0']).to eq "raw payload\n"
    end

    it 'should parse a cached async section like a normal one' do
      # Async/cached plugins tag the header with :cached(ts,age); it must not
      # prevent normal per-section parsing.
      result = CloudModel::CheckMkParser.parse "<<<updates:cached(1700000000,3600)>>>\nreboot_required 1\nsecurity_updates 2\n"
      expect(result['updates']['reboot_required']).to eq '1'
      expect(result['updates']['security_updates']).to eq '2'
    end
  end

  describe '.parse_cgroup_cpu' do
    it 'should return nil when no data key' do
      expect(CloudModel::CheckMkParser.parse_cgroup_cpu({}, 4)).to eq nil
    end

    it 'should set cpus' do
      data = "1000000000 100 200\n0 50 100\n"
      result = {'data' => data}
      CloudModel::CheckMkParser.parse_cgroup_cpu result, 2
      expect(result['cpus']).to eq 2
    end

    it 'should compute usage percentages over the time windows' do
      # base ts in ns; older sample 30s earlier (within all windows)
      base_ts = 100_000_000_000
      old_ts  = base_ts - 30_000_000_000 # 30s earlier
      data = "#{base_ts} 200 200\n#{old_ts} 100 100\n"
      result = {'data' => data}
      CloudModel::CheckMkParser.parse_cgroup_cpu result, 2
      expect(result['last_minute_percentage']).to be_a Numeric
      expect(result['last_minute_percentage_by_cpus']).to be_an Array
      expect(result['last_minute_percentage_by_cpus'].size).to eq 2
      # samples older than 1 min window are nil
      expect(result['last_15_minutes_percentage']).to be_a Numeric
    end

    it 'should return nils for windows with no in-range sample' do
      base_ts = 100_000_000_000
      old_ts  = base_ts - 1_000_000_000_000 # ~1000s earlier, outside all windows
      data = "#{base_ts} 200 200\n#{old_ts} 100 100\n"
      result = {'data' => data}
      CloudModel::CheckMkParser.parse_cgroup_cpu result, 2
      expect(result['last_minute_percentage']).to be_nil
      expect(result['last_5_minutes_percentage']).to be_nil
      expect(result['last_15_minutes_percentage']).to be_nil
    end
  end

  describe '.parse integration with cgroup_cpu' do
    it 'should compute cgroup cpu using cpu section cpus' do
      base_ts = 100_000_000_000
      old_ts  = base_ts - 30_000_000_000
      input = "<<<cpu>>>\n0.5 1.0 1.5 1/200 12345 2\n" \
              "<<<cgroup_cpu>>>\n#{base_ts} 200 200\n#{old_ts} 100 100\n"
      result = CloudModel::CheckMkParser.parse input
      expect(result['cgroup_cpu']['cpus']).to eq '2'
      expect(result['cgroup_cpu']).to have_key 'last_minute_percentage'
    end

    it 'should compute cgroup cpu from a single total value (cgroup v2)' do
      # cgroup v2 emits one aggregate usage value (ns) instead of a per-CPU
      # array; total/wall/cpus still yields the correct overall percentage.
      base_ts = 100_000_000_000
      old_ts  = base_ts - 30_000_000_000
      input = "<<<cpu>>>\n0.5 1.0 1.5 1/200 12345 2\n" \
              "<<<cgroup_cpu>>>\n#{base_ts} 400\n#{old_ts} 200\n"
      result = CloudModel::CheckMkParser.parse input
      expect(result['cgroup_cpu']['cpus']).to eq '2'
      expect(result['cgroup_cpu']['last_minute_percentage']).to be_a Numeric
      expect(result['cgroup_cpu']['last_minute_percentage_by_cpus'].size).to eq 1
    end

    it 'should derive cpu from lxc_container_cpu when cpu section absent' do
      base_ts = 100_000_000_000
      old_ts  = base_ts - 30_000_000_000
      input = "<<<lxc_container_cpu>>>\nnum_cpus 2\n" \
              "<<<cgroup_cpu>>>\n#{base_ts} 200 200\n#{old_ts} 100 100\n"
      result = CloudModel::CheckMkParser.parse input
      expect(result['cgroup_cpu']['cpus']).to eq '2'
      expect(result['cpu']).not_to be_nil
    end
  end
end