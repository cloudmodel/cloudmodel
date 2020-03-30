module CloudModel
  class HostChecks < CloudModel::BaseChecks
    include CloudModel::Mixins::SysinfoChecksMixin
    
    def initialize host, options = {}
      puts "[Host #{host.name}]"
      @indent = 0
      @subject = host
      
      if options[:cached]
        @result = @subject.monitoring_last_check_result
      else
        print "  * Acqire data ..."
        @result = {
          system: @subject.system_info
        }
        puts "[\e[32mDone\e[39m]"
      
        store_check_result
      end
    end
    
    def check_md
      if sys_info = @result[:system] and sys_info['md']
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
      if sys_info = @result[:system] and sys_info['sensors']
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
      if sys_info = @result[:system] and sys_info['smart']
        failures = []
        
        (['sda', 'sdb'] - sys_info['smart'].keys).each do |v|
          failures << "#{v} not found"
        end

        sys_info['smart'].each do |k,v|
          failures << "Test on #{k} not passed (#{v['smart_status']})" unless v['smart_status'].to_s == 'PASSED'
        end
        
        do_check :smart, 'SMART', {critical: not(failures.blank?)}, message: failures * "\n"
      end
    end
    
    def check
      check_system_info
      if @result[:system]
        check_md
        check_sensors
        check_smart
      end
    end
  end
end