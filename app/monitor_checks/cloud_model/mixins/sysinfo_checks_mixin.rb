module CloudModel
  module Mixins
    module SysinfoChecksMixin
      def check_cpu_usage
        if sys_info = @result[:system] and sys_info["cpu"]
          usage = 100.0 * sys_info["cpu"]["last_5_minutes_load"].to_f / sys_info["cpu"]["cpus"].to_i
        
          do_check_value :cpu_usage, usage, {
            critical: 90,
            warning: 70
            }, unit: '%', name: 'CPU usage'
        end
      end
      
      def check_mem_usage
        if sys_info = @result[:system] and sys_info['mem']
          total = sys_info['mem']['mem_total'].to_i
          available = sys_info['mem']['mem_available'].to_i
          usage = 100.0 * (total - available) / total
        
          do_check_value :mem_usage, usage, {
            critical: 90,
            warning: 70
            }, unit: '%'
        end
      end
      
      def check_disks_usage
        if sys_info = @result[:system] and sys_info['df']
          disks_usage = []
          sys_info['df'].each do |k, df|
            size = df['size'].to_i
            if @subject.is_a? CloudModel::Guest and vol = @subject.lxd_custom_volumes.to_a.find{|v| "/#{v.mount_point}" == df['mountpoint']}
              size = vol.disk_space / 1024
            end
                        
            disks_usage << [ k, 100.0*df['used'].to_i/size ] unless size == 0
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
        sys_info = @result[:system]
                
        if do_check :sys_info_available, 'Check system information', {fatal: not(sys_info["error"].blank?)}, message: sys_info["error"]
          check_cpu_usage
          check_mem_usage
          check_disks_usage
        end
      end
    end
  end
end