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
                "Device Model: Samsung SSD 860\n" \
                "Reallocated_Sector_Ct: 0 some extra\n"
        result = CloudModel::CheckMkParser.parse input
        expect(result['smart']['sda']['device_model']).to eq 'Samsung'
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