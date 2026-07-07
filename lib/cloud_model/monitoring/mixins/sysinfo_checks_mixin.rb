module CloudModel
  module Monitoring
    module Mixins
      module SysinfoChecksMixin
        def check_cpu_usage
          if sys_info = data[:system] and sys_info["cgroup_cpu"]
            if sys_info["cgroup_cpu"]["last_minute_percentage"]
              usage = sys_info["cgroup_cpu"]["last_minute_percentage"].to_f

              do_check_value "cpu_minute_usage".to_sym, usage, {
                critical: 98,
                warning: 95
                }, unit: '%', name: "CPU usage (1 Minute)"
            end

            if sys_info["cgroup_cpu"]["last_5_minutes_percentage"]
              usage = sys_info["cgroup_cpu"]["last_5_minutes_percentage"].to_f

              do_check_value "cpu_5_minutes_usage".to_sym, usage, {
                critical: 95,
                warning: 80
                }, unit: '%', name: "CPU usage (5 Minutes)"
            end

            if sys_info["cgroup_cpu"]["last_15_minutes_percentage"]
              usage = sys_info["cgroup_cpu"]["last_15_minutes_percentage"].to_f

              do_check_value "cpu_15_minutes_usage".to_sym, usage, {
                critical: 90,
                warning: 70
                }, unit: '%', name: "CPU usage (15 Minutes)"
            end
          end
        end

        def check_mem_usage
          if sys_info = data[:system] and sys_info['mem']
            total = sys_info['mem']['mem_total'].to_i
            available = sys_info['mem']['mem_available'].to_i
            usage = 100.0 * (total - available) / total

            do_check_value :mem_usage, usage, {
              critical: 95,
              warning: 90
              }, unit: '%'
          end
        end

        def check_disks_usage
          if sys_info = data[:system] and sys_info['df']
            disks_usage = []
            sys_info['df'].each do |k, df|
              unless k  =~ /^\/dev\/loop.?/
                size = df['size'].to_i
                if @subject.is_a? CloudModel::Guest and vol = @subject.lxd_custom_volumes.to_a.find{|v| "/#{v.mount_point}" == df['mountpoint']}
                  size = vol.disk_space / 1024
                end

                disks_usage << [ k, 100.0*df['used'].to_i/size ] unless size == 0
              end
            end

            disks_usage.sort!{|a,b| b[1] <=> a[1]}
            usage = disks_usage.first.last

            message = ""
            disks_usage.each do |k,v|
              message << "#{k}: #{"#{"%0.2f" % (v)}%"}\n"
            end

            do_check_value :disks_usage, usage, {
              critical: 90,
              warning: 80
              }, unit: '%', message: message
          end
        end

        def check_swap_usage
          if sys_info = data[:system] and mem = sys_info['mem']
            total = mem['swap_total'].to_i
            return if total == 0 # no swap configured

            free = mem['swap_free'].to_i
            usage = 100.0 * (total - free) / total

            do_check_value :swap_usage, usage, {
              critical: 90,
              warning: 75
              }, unit: '%'
          end
        end

        def check_load
          # Guests: without lxcfs loadavg virtualisation (`lxcfs -l`, not the
          # LXD snap default) /proc/loadavg inside a container shows the HOST
          # load, while cpuinfo shows the guest's limited core count — the
          # ratio then fires on every guest of a busy host at once. Alert on
          # hosts only; resolve any issues from when this ran on guests.
          if @subject.is_a? CloudModel::Guest
            if issue = @subject.item_issues.where(key: :load_per_core, resolved_at: nil).first
              issue.update_attribute :resolved_at, Time.now
            end
            return
          end

          if sys_info = data[:system] and cpu = sys_info['cpu']
            cpus = cpu['cpus'].to_i
            return if cpus == 0

            load15 = cpu['last_15_minutes_load'].to_f
            per_core = load15 / cpus

            # Load is CPU + uninterruptible I/O wait, so it catches saturation
            # (e.g. disk-bound) that the cgroup CPU% check misses. Normalised
            # per core: 1.0/core is a fully-but-healthily-busy host, so alert
            # only well above that (2×/4× capacity) to avoid paging on load that
            # merely reflects a busy — not overloaded — system.
            do_check_value :load_per_core, per_core, {
              critical: 4.0,
              warning: 2.0
              }, name: 'Load average per core (15m)',
              message: "15m load #{load15} on #{cpus} cores (#{"%0.2f" % per_core}/core)"
          end
        end

        def check_inodes_usage
          if sys_info = data[:system] and sys_info['df_inodes']
            inodes_usage = []
            sys_info['df_inodes'].each do |k, df|
              next if k =~ /^\/dev\/loop.?/
              size = df['size'].to_i
              inodes_usage << [ df['mountpoint'] || k, 100.0 * df['used'].to_i / size ] unless size == 0
            end
            return if inodes_usage.empty?

            inodes_usage.sort! { |a, b| b[1] <=> a[1] }
            message = inodes_usage.map { |k, v| "#{k}: #{"%0.2f" % v}%" } * "\n"

            do_check_value :inodes_usage, inodes_usage.first.last, {
              critical: 90,
              warning: 80
              }, unit: '%', name: 'Inode usage', message: message
          end
        end

        # Unit names to suppress in the failed-units check (known-benign/expected
        # failures). Extend per environment. Kept as an explicit knob so ops can
        # silence a specific noisy unit without disabling the whole check.
        SYSTEMD_IGNORE = %w().freeze

        def check_systemd_units
          if sys_info = data[:system] and units = sys_info['systemd']
            failed = units.select do |name, u|
              (u['active'] == 'failed' or u['sub'] == 'failed') and
                # transient/session scopes and device/slice units produce noisy
                # non-actionable "failed" states; alert on real units only.
                name !~ /\.(scope|device|slice)\z/ and
                not SYSTEMD_IGNORE.include?(name)
            end.keys

            do_check :systemd_failed, 'Failed systemd units', {
              warning: not(failed.blank?)
              }, message: failed * "\n", value: failed.size.to_s
          end
        end

        def check_readonly_fs
          if sys_info = data[:system] and mounts = sys_info['mounts']
            writable_fs = %w(ext2 ext3 ext4 xfs btrfs zfs reiserfs)
            readonly = mounts.select do |_dev, m|
              writable_fs.include?(m['format']) and (m['params'] || '').split(',').include?('ro')
            end.map { |_dev, m| "#{m['mountpoint']} (#{m['format']})" }

            do_check :readonly_fs, 'Read-only filesystems', {
              critical: not(readonly.blank?)
              }, message: readonly * "\n"
          end
        end

        # Per-second rate of one cumulative counter between the previous and the
        # current monitoring cycle. The snapshot of the previous cycle's parsed
        # data + timestamp (`@prev_system` / `@prev_at`) is captured in the
        # subject's `#check` before fresh data overwrites it. Returns nil when
        # there is no comparable previous value, no elapsed time, or after a
        # counter reset (reboot → negative delta, clamped to 0). Shared by host
        # and guest rate checks.
        # @return [Float, nil]
        def counter_rate cur, prev
          return nil if cur.nil? or prev.nil? or @prev_at.nil?

          elapsed = ((@subject.monitoring_last_check_at || Time.now) - @prev_at).to_f
          return nil unless elapsed > 0

          delta = cur.to_i - prev.to_i
          delta = 0 if delta < 0 # counter reset (reboot)
          delta / elapsed
        end

        # Per-container cgroup limit signals (from the `cgroup_limits` plugin,
        # guests only). Only the clear, actionable failures are alerted:
        # approaching the PID wall (can't fork) and in-container OOM kills (a
        # process was killed). Memory-limit pressure (failcnt/events) and CPU
        # throttling are recorded as metrics only — for an intentionally
        # right-sized container both are routinely non-zero, so alerting on them
        # is pure noise; the graphs are where you spot chronic starvation.
        def check_cgroup_limits
          return unless sys_info = data[:system] and cg = sys_info['cgroup_limits']

          prev = (@prev_system && @prev_system['cgroup_limits']) || {}

          # PID/thread exhaustion: current vs max ('max' = unlimited → skip).
          if cg['pids_max'] and cg['pids_max'] != 'max' and cg['pids_max'].to_i > 0
            usage = 100.0 * cg['pids_current'].to_i / cg['pids_max'].to_i
            do_check_value :cgroup_pids, usage, {
              critical: 90,
              warning: 80
              }, unit: '%', name: 'PID usage',
              message: "#{cg['pids_current']} / #{cg['pids_max']} PIDs"
          end

          # In-container OOM kills (cgroup v2; v1 guests are covered by the host
          # kernel_log check). Warning — matching the host OOM treatment: a
          # process was killed and is worth surfacing, but many workloads
          # tolerate the odd OOM so it should not page.
          if rate = counter_rate(cg['oom_kills'], prev['oom_kills'])
            do_check :cgroup_oom, 'In-container OOM kills', {
              warning: rate > 0
              }, value: "#{"%0.3f" % rate}/s"
          end
        end

        # Mountpoints excluded from the per-mount disk/inode sample series:
        # virtual filesystems and LXD container/snap internals (a host easily
        # has 100+ container rootfs mounts, all mirroring the pool usage —
        # they'd drown the disk chart). Alerting (check_disks_usage) is not
        # affected by this filter.
        SAMPLE_MOUNT_IGNORE = %r{\A/(dev|run|sys|proc|snap)(/|\z)|\A/var/lib/lxd/storage-pools/|\A/var/snap/lxd/common/}

        # Numeric metrics shared by hosts and guests, derived from the parsed
        # check_mk `system` section: CPU load & usage, memory usage and per-mount
        # disk usage. Used to build time-series samples for graphing.
        # @return [Hash{String=>Float}]
        def sysinfo_sample_metrics
          metrics = {}
          return metrics unless sys_info = data[:system]

          if cpu = sys_info['cpu']
            metrics['cpu.load_1'] = cpu['last_minute_load'].to_f if cpu['last_minute_load']
            metrics['cpu.load_5'] = cpu['last_5_minutes_load'].to_f if cpu['last_5_minutes_load']
            metrics['cpu.load_15'] = cpu['last_15_minutes_load'].to_f if cpu['last_15_minutes_load']
          end

          if cgroup = sys_info['cgroup_cpu']
            metrics['cpu.usage_1'] = cgroup['last_minute_percentage'].to_f if cgroup['last_minute_percentage']
            metrics['cpu.usage_5'] = cgroup['last_5_minutes_percentage'].to_f if cgroup['last_5_minutes_percentage']
            metrics['cpu.usage_15'] = cgroup['last_15_minutes_percentage'].to_f if cgroup['last_15_minutes_percentage']
          end

          if mem = sys_info['mem']
            total = mem['mem_total'].to_i
            available = mem['mem_available'].to_i
            if total > 0
              metrics['mem.usage'] = 100.0 * (total - available) / total
            end

            swap_total = mem['swap_total'].to_i
            if swap_total > 0
              metrics['swap.usage'] = 100.0 * (swap_total - mem['swap_free'].to_i) / swap_total
            end
          end

          # load-per-core only for hosts — on guests the loadavg is the host's
          # (lxcfs default), so the ratio against guest cores is meaningless.
          if !@subject.is_a?(CloudModel::Guest) and cpu = sys_info['cpu'] and (cpus = cpu['cpus'].to_i) > 0
            metrics['cpu.load_per_core'] = cpu['last_15_minutes_load'].to_f / cpus
          end

          if sys_info['df_inodes']
            sys_info['df_inodes'].each do |mount, df|
              next if mount =~ /^\/dev\/loop.?/
              next if df['mountpoint'] and df['mountpoint'] =~ SAMPLE_MOUNT_IGNORE
              size = df['size'].to_i
              next if size == 0
              metrics["inode.#{df['mountpoint'] || mount}.usage"] = 100.0 * df['used'].to_i / size
            end
          end

          if cg = sys_info['cgroup_limits']
            if cg['pids_max'] and cg['pids_max'] != 'max' and cg['pids_max'].to_i > 0
              metrics['cgroup.pids_usage'] = 100.0 * cg['pids_current'].to_i / cg['pids_max'].to_i
            end
            prev = (@prev_system && @prev_system['cgroup_limits']) || {}
            { 'mem_hits' => 'mem_pressure_rate', 'oom_kills' => 'oom_rate', 'cpu_nr_throttled' => 'cpu_throttle_rate' }.each do |key, metric|
              if r = counter_rate(cg[key], prev[key])
                metrics["cgroup.#{metric}"] = r
              end
            end
          end

          if sys_info['df']
            sys_info['df'].each do |mount, df|
              next if mount =~ /^\/dev\/loop.?/
              next if df['mountpoint'] and df['mountpoint'] =~ SAMPLE_MOUNT_IGNORE
              size = df['size'].to_i
              next if size == 0
              metrics["disk.#{df['mountpoint'] || mount}.usage"] = 100.0 * df['used'].to_i / size
            end
          end

          metrics
        end

        def check_system_info
          sys_info = data[:system]

          if do_check :sys_info_available, 'Check system information', {fatal: not(sys_info["error"].blank?)}, message: sys_info["error"]
            check_cpu_usage
            check_mem_usage
            check_swap_usage
            check_load
            check_disks_usage
            check_inodes_usage
            check_systemd_units
            check_readonly_fs
            check_cgroup_limits
            true
          end
        end
      end
    end
  end
end