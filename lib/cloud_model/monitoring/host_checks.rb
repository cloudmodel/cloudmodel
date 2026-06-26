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

      def check
        if check_system_info
          check_md
          check_sensors
          check_smart
          check_zpools
          true
        else
          false
        end

      end
    end
  end
end