module CloudModel
  module Monitoring
    class HostChecks < CloudModel::Monitoring::BaseChecks
      require_relative "mixins/sysinfo_checks_mixin" unless Rails.env.development?
      include CloudModel::Monitoring::Mixins::SysinfoChecksMixin

      def self.check options = {}
        threads = []

        CloudModel::Host.scoped.each do |host|
          unless [:booting, :not_started].include?(host.deploy_state)
            puts "[_Monitoring_] Threading #{host}"
            threads << Thread.new do
              Rails.application.executor.wrap do
                handle_cloudmodel_monitoring_exception host, host, 2 do
                  if CloudModel::Monitoring::HostChecks.new(host).check
                    host.guests.each do |guest|
                      handle_cloudmodel_monitoring_exception guest, host, 4 do
                        if CloudModel::Monitoring::GuestChecks.new(guest).check
                          guest.lxd_custom_volumes.each do |lxd_custom_volume|
                            handle_cloudmodel_monitoring_exception lxd_custom_volume, host, 6 do
                              CloudModel::Monitoring::LxdCustomVolumeChecks.new(lxd_custom_volume).check
                            end
                          end
                          guest.services.each do |service|
                            handle_cloudmodel_monitoring_exception service, host, 6 do
                              CloudModel::Monitoring::ServiceChecks.new(service).check
                            end
                          end
                        end
                      end
                    end
                  end
                  puts "[#{host.name}] Done."
                end
              end
            end
          end
        end
        threads.each(&:join)
      end

      def line_prefix
        "[#{@subject.name}] #{super}"
      end

      def acquire_data
        {
          system: @subject.system_info
        }
      end

      def sample_metrics
        metrics = sysinfo_sample_metrics

        if sys_info = data[:system]
          if ct = sys_info['nf_conntrack'] and ct['max'].to_i > 0
            metrics['conntrack.usage'] = 100.0 * ct['count'].to_i / ct['max'].to_i
          end

          conntrack_rates.each do |name, rate|
            metrics["conntrack.#{name}_rate"] = rate
          end

          net_dev_rates.each do |iface, r|
            %w(rx_bytes tx_bytes rx_errs tx_errs rx_drop tx_drop).each do |k|
              metrics["net.#{iface}.#{k}"] = r[k] if r[k]
            end
          end

          diskstats_rates.each do |dev, r|
            %w(read_bytes write_bytes iops await).each do |k|
              metrics["disk.#{dev}.#{k}"] = r[k] if r[k]
            end
          end

          if sys_info['zpools']
            sys_info['zpools'].each do |pool_name, pool_data|
              if pool_data[:cap_percentage]
                metrics["zpool.#{pool_name}.cap"] = pool_data[:cap_percentage].to_f
              end
            end
          end

          if sys_info['sensors']
            sys_info['sensors'].each do |name, sensor|
              if sensor['type'] == 'temp' and sensor['input']
                metrics["sensor.#{name}"] = sensor['input'].to_f
              end
            end
          end

          if sys_info['smart']
            sys_info['smart'].each do |dev, values|
              if temp = smart_temperature(values)
                metrics["smart.#{dev}.temp"] = temp
              end

              # Wear indicators as time series — the trend (are the 16
              # reallocated sectors growing?) is what makes a smart_trending
              # issue actionable.
              SMART_WEAR_METRICS.each do |attr|
                metrics["smart.#{dev}.#{attr}"] = values[attr].to_f if values[attr]
              end
            end
          end
        end

        metrics
      end

      # Representative disk temperature (°C) from a SMART entry, mirroring the
      # precedence used in the host view. Returns nil when no usable reading.
      def smart_temperature values
        temp = if values['temperature_sensor_1'] and values['temperature_sensor_2']
          [values['temperature_sensor_1'].to_f, values['temperature_sensor_2'].to_f].max
        elsif values['temperature']
          values['temperature'].to_f
        elsif values['temperature_celsius']
          values['temperature_celsius'].to_f
        end
        temp if temp and temp > 0
      end

      def check_md
        if sys_info = data[:system] and sys_info['md']
          failures = []

          (['md0', 'md1', 'md2', 'md3', 'md4'] - sys_info['md']['devs'].keys).each do |v|
            failures << "#{v} not found"
          end

          sys_info['md']['devs'].each do |k,v|
            if v['status'] != 'active'
              failures << "#{k} not active"
            end
          end

          do_check :mdtools, 'RAID', {critical: not(failures.blank?)}, message: failures * "\n"
        end
      end

      def check_sensors
        if sys_info = data[:system] and sys_info['sensors']
          failures = []

          sys_info['sensors'].each do |k, sensor|
            if sensor['input'] and sensor['max'] and sensor['max'] != 0.0 and sensor['input']>sensor['max']
              failures << "#{k} to high: #{sensor['input']} > #{sensor['max']}"
            end
            if sensor['input'] and sensor['min'] and sensor['input']<sensor['min']
              failures << "#{k} to low: #{sensor['input']} < #{sensor['min']}"
            end
          end

          do_check :sensors, 'Sensors', {warning: not(failures.blank?)}, message: failures * "\n"
        end
      end

      def check_smart
        if sys_info = data[:system] and sys_info['smart']
          failures = []

          (@subject.system_disks - sys_info['smart'].keys).each do |v|
            failures << "#{v} not found"
          end

          sys_info['smart'].each do |k,v|
            failures << "Test on #{k} not passed (#{v['smart_status']})" unless v['smart_status'].to_s == 'PASSED'
          end

          do_check :smart, 'SMART', {critical: not(failures.blank?)}, message: failures * "\n"
        end
      end

      def check_zpools
        if sys_info = data[:system] and sys_info['zpools']
          usages = [0]
          messages = []
          sys_info['zpools'].each do |pool_name, pool_data|
            messages << "#{pool_name}: #{pool_data[:cap_percentage]}%"
            usages << pool_data[:cap_percentage].to_f
          end

          do_check_value :zpools_usage, usages.max, {
            critical: 90,
            warning: 75
            }, unit: '%', message: messages * "\n"
        end
      end

      # Virtual/per-guest network interfaces to ignore for net_dev monitoring:
      # loopback, LXD veth pairs, tunnels and other software devices. Only
      # physical NICs and bridges (eth0, lxdbr0, bond*) are kept.
      NET_DEV_VIRTUAL = /\A(lo|veth|tap|tun|vnet|docker|virbr|vif)/

      # Whole disks (not partitions) for I/O latency/throughput monitoring.
      DISKSTATS_WHOLE = /\A(sd[a-z]+|nvme\d+n\d+|vd[a-z]+|xvd[a-z]+)\z/

      # SMART wear attributes recorded as time series (ATA + NVMe) — the same
      # ones check_smart_trending alerts on.
      SMART_WEAR_METRICS = %w(reallocated_sector_ct current_pending_sector
                              offline_uncorrectable reported_uncorrect
                              media_and_data_integrity_errors percentage_used).freeze

      # Per-second rates of the cumulative conntrack counters. Rates — not the
      # raw cumulative counters — are what we alert and graph on, mirroring
      # node_exporter's `nf_conntrack_stat_*` metrics. Empty on the first cycle
      # or after a counter reset.
      # @return [Hash{String=>Float}]
      def conntrack_rates
        return @conntrack_rates if defined? @conntrack_rates
        @conntrack_rates = {}

        ct = data[:system] && data[:system]['nf_conntrack']
        prev = @prev_system && @prev_system['nf_conntrack']
        return @conntrack_rates unless ct and prev

        %w(drop insert_failed early_drop invalid search_restart).each do |name|
          if rate = counter_rate(ct[name], prev[name])
            @conntrack_rates[name] = rate
          end
        end

        @conntrack_rates
      end

      # Per-interface per-second rates (rx/tx bytes, packets, errs, drop) from
      # /proc/net/dev, for physical/bridge interfaces only ({NET_DEV_VIRTUAL}
      # excluded). Mirrors node_exporter's `node_network_*_total` metrics. Empty
      # on the first cycle.
      # @return [Hash{String=>Hash{String=>Float}}]
      def net_dev_rates
        return @net_dev_rates if defined? @net_dev_rates
        @net_dev_rates = {}

        cur = data[:system] && data[:system]['net_dev']
        prev = @prev_system && @prev_system['net_dev']
        return @net_dev_rates unless cur and prev

        cur.each do |iface, counters|
          next if iface =~ NET_DEV_VIRTUAL or prev[iface].nil?

          rates = {}
          %w(rx_bytes tx_bytes rx_packets tx_packets rx_errs tx_errs rx_drop tx_drop).each do |k|
            if rate = counter_rate(counters[k], prev[iface][k])
              rates[k] = rate
            end
          end

          @net_dev_rates[iface] = rates unless rates.empty?
        end

        @net_dev_rates
      end

      # Alert on interface receive/transmit error and drop ratios relative to
      # the packet rate (node_exporter NodeNetworkReceiveErrs style): a healthy
      # link sits at ~0%, sustained errors indicate bad cabling/NIC/driver.
      # Interfaces below 1 packet/s are skipped (too little traffic to judge).
      def check_net_dev
        net_dev_rates.each do |iface, r|
          %w(rx tx).each do |dir|
            packets = r["#{dir}_packets"]
            next if packets.nil? or packets < 1

            {'errs' => 'errors', 'drop' => 'drops'}.each do |kind, label|
              rate = r["#{dir}_#{kind}"]
              next if rate.nil?

              ratio = 100.0 * rate / packets
              do_check_value :"net_#{iface}_#{dir}_#{kind}", ratio, {
                critical: 5,
                warning: 1
                }, unit: '%', name: "#{iface} #{dir} #{label}",
                message: "%0.2f%% of %s %s packets are %s (%0.2f/s)" % [ratio, iface, dir, label, rate]
            end
          end
        end
      end

      def check_conntrack
        return unless sys_info = data[:system] and ct = sys_info['nf_conntrack']

        # Leading indicator: table fill level. Warn at 75% (kube-prometheus
        # NodeHighNumberConntrackEntriesUsed default), critical at 90%.
        if ct['max'].to_i > 0
          usage = 100.0 * ct['count'].to_i / ct['max'].to_i

          do_check_value :conntrack_usage, usage, {
            critical: 90,
            warning: 75
            }, unit: '%', name: 'Conntrack table usage',
            message: "#{ct['count']} / #{ct['max']} tracked connections"
        end

        rates = conntrack_rates

        # Ground truth of lost connections: insert_failed means the table was
        # full when a new connection arrived, so it was never tracked (and, for
        # NAT, its packets get dropped). Any occurrence is a warning; a sustained
        # rate is critical. Catches burst exhaustion the usage gauge misses.
        if rate = rates['insert_failed']
          do_check_value :conntrack_insert_failed, rate, {
            critical: 1,
            warning: 0
            }, unit: '/s', name: 'Conntrack insert failures',
            message: "%0.3f failed inserts/s (table full on insert)" % rate
        end

        # Packets dropped on the conntrack path (new-entry allocation failure).
        if rate = rates['drop']
          do_check_value :conntrack_drop, rate, {
            critical: 1,
            warning: 0
            }, unit: '/s', name: 'Conntrack drops',
            message: "%0.3f dropped packets/s" % rate
        end
      end

      # A degraded/faulted pool (e.g. a failed disk in a mirror) still serves
      # data, so it is otherwise completely silent — capacity alone never
      # catches it. Alert on any non-ONLINE pool health.
      def check_zpool_health
        if sys_info = data[:system] and pools = sys_info['zpools']
          unhealthy = pools.reject { |_name, p| p[:health] == 'ONLINE' }
                           .map { |name, p| "#{name}: #{p[:health]}" }

          do_check :zpools_health, 'ZFS pool health', {
            critical: not(unhealthy.blank?)
            }, message: unhealthy * "\n"
        end
      end

      # SMART pass/fail flips only at the very end of a disk's life. These
      # attributes rise well before that — a growing reallocated/pending sector
      # count is the early warning to replace the disk.
      def check_smart_trending
        if sys_info = data[:system] and smart = sys_info['smart']
          problems = []
          smart.each do |dev, v|
            # ATA/SATA wear attributes: any non-zero value is an early warning.
            %w(reallocated_sector_ct current_pending_sector offline_uncorrectable reported_uncorrect).each do |attr|
              problems << "#{dev} #{attr}=#{v[attr]}" if v[attr] and v[attr].to_i > 0
            end

            # NVMe health (different attribute set than ATA).
            if v['media_and_data_integrity_errors'] and v['media_and_data_integrity_errors'].to_i > 0
              problems << "#{dev} media_and_data_integrity_errors=#{v['media_and_data_integrity_errors']}"
            end
            if v['percentage_used'] and v['percentage_used'].to_i >= 100
              problems << "#{dev} percentage_used=#{v['percentage_used']} (endurance exceeded)"
            end
            if v['available_spare'] and v['available_spare_threshold'] and
               v['available_spare'].to_i < v['available_spare_threshold'].to_i
              problems << "#{dev} available_spare=#{v['available_spare']} < threshold #{v['available_spare_threshold']}"
            end
          end

          do_check :smart_trending, 'SMART wear indicators', {
            warning: not(problems.blank?)
            }, message: problems * "\n"
        end
      end

      def check_ntp
        if sys_info = data[:system] and ntp = sys_info['ntp']
          if synced = ntp['NTPSynchronized']
            # Clock drift breaks TLS and TOTP 2FA (the auth service).
            do_check :ntp_sync, 'Time synchronisation', {
              warning: synced != 'yes'
              }, message: 'System clock is not NTP-synchronised', value: synced
          end

          if offset = ntp['offset']
            do_check_value :ntp_offset, offset.to_f.abs, {
              critical: 1.0,
              warning: 0.5
              }, unit: 's', name: 'Clock offset'
          end
        end
      end

      # Kernel-log signatures that are otherwise invisible: OOM kills, hardware/
      # machine-check errors, block-I/O errors and filesystem corruption. Alerts
      # on any increase since the previous cycle (rate > 0).
      def check_kernel_log
        cur = data[:system] && data[:system]['kernel_log']
        prev = @prev_system && @prev_system['kernel_log']
        return unless cur and prev

        {
          'mce'      => [:critical, 'Machine-check / hardware errors'],
          'fs_error' => [:critical, 'Filesystem errors'],
          'oom'      => [:warning,  'Out-of-memory kills'],
          'io_error' => [:warning,  'Block I/O errors']
        }.each do |key, (severity, name)|
          rate = counter_rate(cur[key], prev[key])
          next if rate.nil?

          do_check :"kernel_#{key}", name, {
            severity => rate > 0
            }, message: "#{name} appeared in the kernel log", value: "#{"%0.3f" % rate}/s"
        end
      end

      # Per-whole-disk I/O rates from /proc/diskstats. `await` is the average
      # time an I/O spends in the queue + service (ms) — the meaningful latency
      # signal (unlike %util, which saturates harmlessly on SSD/NVMe).
      def diskstats_rates
        return @diskstats_rates if defined? @diskstats_rates
        @diskstats_rates = {}

        cur = data[:system] && data[:system]['diskstats']
        prev = @prev_system && @prev_system['diskstats']
        return @diskstats_rates unless cur and prev

        cur.each do |dev, c|
          next unless dev =~ DISKSTATS_WHOLE and prev[dev]
          p = prev[dev]

          r = {}
          if b = counter_rate(c['sectors_read'], p['sectors_read']);    r['read_bytes']  = b * 512; end
          if b = counter_rate(c['sectors_written'], p['sectors_written']); r['write_bytes'] = b * 512; end

          reads  = counter_rate(c['reads'], p['reads'])
          writes = counter_rate(c['writes'], p['writes'])
          msr    = counter_rate(c['ms_reading'], p['ms_reading'])
          msw    = counter_rate(c['ms_writing'], p['ms_writing'])
          iops   = (reads || 0) + (writes || 0)
          r['iops'] = iops
          r['await'] = (msr + msw) / iops if iops > 0 and msr and msw

          @diskstats_rates[dev] = r unless r.empty?
        end

        @diskstats_rates
      end

      def check_diskstats
        diskstats_rates.each do |dev, r|
          next unless r['await']

          do_check_value :"disk_#{dev}_await", r['await'], {
            critical: 500,
            warning: 100
            }, unit: 'ms', name: "#{dev} I/O latency",
            message: "avg I/O wait #{"%0.1f" % r['await']}ms at #{"%0.0f" % (r['iops'] || 0)} IOPS"
        end
      end

      # A physical interface reporting operstate 'down' that has carried traffic
      # (rx/tx bytes > 0) is a real link loss. Interfaces that were never up
      # (unused/spare NICs) have zero counters and are ignored — otherwise every
      # host with a cabled-but-unconfigured second NIC would page. The frozen
      # counters keep the alert firing for as long as the link stays down.
      def check_net_links
        if sys_info = data[:system] and nd = sys_info['net_dev']
          down = nd.select do |iface, c|
            c['operstate'] == 'down' and iface !~ NET_DEV_VIRTUAL and
              (c['rx_bytes'].to_i > 0 or c['tx_bytes'].to_i > 0)
          end.keys

          do_check :net_links_down, 'Network links', {
            critical: not(down.blank?)
            }, message: down * "\n"
        end
      end

      def check_updates
        if sys_info = data[:system] and up = sys_info['updates']
          if up['reboot_required']
            do_check :reboot_required, 'Reboot required', {
              task: up['reboot_required'].to_i > 0
              }, message: 'A package (e.g. kernel) requires a reboot'
          end

          if up['security_updates']
            n = up['security_updates'].to_i
            do_check :security_updates, 'Pending security updates', {
              task: n > 0
              }, value: n.to_s, message: "#{n} security updates pending"
          end
        end
      end

      def check_edac
        cur = data[:system] && data[:system]['edac']
        return unless cur

        # Uncorrectable (UE) errors mean data corruption — page immediately.
        do_check :ecc_uncorrectable, 'ECC uncorrectable errors', {
          critical: cur['ue_count'].to_i > 0
          }, value: cur['ue_count']

        # A rising corrected (CE) error rate warns of a failing DIMM.
        if prev = @prev_system && @prev_system['edac'] and rate = counter_rate(cur['ce_count'], prev['ce_count'])
          do_check :ecc_corrected, 'ECC corrected error rate', {
            warning: rate > 0
            }, value: "#{"%0.3f" % rate}/s"
        end
      end

      # Cache the core count (from the agent's cpu section) on the host record
      # so list views can show it without an SSH round-trip. The smart getter
      # on Host#cpu_count probes lazily but never saves; reading the raw field
      # here avoids triggering that probe.
      def persist_cpu_count
        cpu = data[:system] && data[:system]['cpu']
        cpus = cpu && cpu['cpus'].to_i
        return unless cpus and cpus > 0

        @subject.update_attribute :cpu_count, cpus if @subject[:cpu_count] != cpus
      end

      def check
        # Snapshot the previous cycle's parsed system data + timestamp before
        # #check_system_info acquires fresh data and overwrites them; needed to
        # turn the cumulative conntrack/net_dev/diskstats/kernel/edac counters
        # into rates (see #counter_rate). The stored result wraps the sections
        # in a 'system' level (string key after the MongoDB round-trip).
        prev = @subject.monitoring_last_check_result
        @prev_system = prev && (prev['system'] || prev[:system])
        @prev_at = @subject.monitoring_last_check_at

        if check_system_info
          persist_cpu_count
          check_md
          check_sensors
          check_smart
          check_smart_trending
          check_zpools
          check_zpool_health
          check_conntrack
          check_net_dev
          check_net_links
          check_ntp
          check_kernel_log
          check_diskstats
          check_updates
          check_edac
          true
        else
          false
        end

      end
    end
  end
end