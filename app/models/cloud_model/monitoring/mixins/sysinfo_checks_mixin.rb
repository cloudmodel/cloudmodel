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
              critical: 90,
              warning: 80
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
              warning: 70
              }, unit: '%', message: message
          end
        end

        def check_system_info
          sys_info = data[:system]

          if do_check :sys_info_available, 'Check system information', {fatal: not(sys_info["error"].blank?)}, message: sys_info["error"]
            check_cpu_usage
            check_mem_usage
            check_disks_usage
          end
        end
      end
    end
  end
end