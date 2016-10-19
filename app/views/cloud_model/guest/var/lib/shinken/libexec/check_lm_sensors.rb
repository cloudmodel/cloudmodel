#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../check_mk_helpers', __FILE__)

def parse_options
  options = {warn: 80, crit: 90}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-d", "--device DEVICE", "device to check") do |v|
      options[:dev] = v
    end
  end.parse!
  
  options
end

def parse_sensors data
  adapter = nil
  sensor = nil
  result = {}
  sensor_result = nil
  
  data.lines.each do |line|
    if adapter.nil?
      adapter = line
      next
    end
    
    if line.strip.empty?
      adapter = nil
      next
    end
    
    if adapter
      k,v = line.strip.split(':')
    
      if v.nil?
        if sensor
          result[sensor] = sensor_result
        end
        sensor = k
        sensor_result = {'adapter' => adapter, 'label' => sensor}
      else
        if sensor_result
          null, type, null, label = k.strip.match(/([a-z]*)([0-9]*_)(.*)/).to_a
          sensor_result['type'] = type unless type.nil?
          sensor_result[label] = v.to_f
        end
      end
    end
  end
  if sensor
    result[sensor] = sensor_result
  end
  
  result
end

def perfdata_sensors data
  result = {}
  
  data.each do |k,v|
    unless v['input'].nil?
      result[v['type']] ||= {}
      result[v['type']][v['label']] = v['input'] 
    end
  end
  
  perfdata result
end

options = parse_options
failures = []
warnings = []

check_mk_result = query_check_mk(options[:host])
result = filter_check_mk(check_mk_result, 'sensors')
data = parse_sensors result


data.each do |k, sensor|
  if sensor['input'] and sensor['max'] and sensor['max'] != 0.0 and sensor['input']>sensor['max']
    failures << "#{k} to high: #{sensor['input']} > #{sensor['max']}"
  end
  if sensor['input'] and sensor['min'] and sensor['input']<sensor['min']
    failures << "#{k} to low: #{sensor['input']} < #{sensor['min']}"
  end
end

if failures.empty?
  if warnings.empty?
    puts "OK - OK | #{perfdata_sensors data}"
    exit STATE_OK
  else
    puts "WARNING - #{warnings * ', '} | #{perfdata_sensors data}"
    exit STATE_WARNING
  end
else
  puts "CRITICAL - #{(failures+warnings) * ', '} | #{perfdata_sensors data}"
  exit STATE_CRITICAL
end
  