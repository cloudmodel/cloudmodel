#!/bin/env ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)
require 'net/http'

def parse_options
  options = {warn: 80, crit: 90}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-w", "--warn WARNING", "warning level in percent") do |v|
      options[:warn] = v.to_i
    end
    opts.on("-c", "--crit CRITICAL", "critical level in percent") do |v|
      options[:crit] = v.to_i
    end
  end.parse!
  
  options
end

options = parse_options

begin
  raise "No Host given" unless options[:host]
  
  data={}


rescue Exception => e
  puts "WARNING - #{e} | #{perfdata data}"
  exit STATE_WARNING
end

data = retrieve_data_from_oids(
  { 
    '1.3.6.1.4.1.2021.10.1.3.1' => :load_1_min,
    '1.3.6.1.4.1.2021.10.1.3.2' => :load_5_min,
    '1.3.6.1.4.1.2021.10.1.3.3' => :load_15_min,
    '1.3.6.1.4.1.2021.11.11.0'  => :cpu_idle,
    '1.3.6.1.4.1.2021.11.9.0'   => :cpu_user,
    '1.3.6.1.4.1.2021.11.10.0'  => :cpu_system,
    '1.3.6.1.4.1.2021.11.53.0'  => :raw_cpu_time_idle,
    '1.3.6.1.4.1.2021.11.50.0'  => :raw_cpu_time_user,
    '1.3.6.1.4.1.2021.11.52.0'  => :raw_cpu_time_system,
    '1.3.6.1.4.1.2021.11.51.0'  => :raw_cpu_time_nice,
  
    '1.3.6.1.2.1.1.3.0'         => :uptime
  }, options
)

data.merge! retrieve_data_from_oid_multi_to('core_cpu', '1.3.6.1.2.1.25.3.3.1.2', options)

# # TODO: Move this to somewhere else
# data['uptime'] = "\"#{data['uptime']}\""

cpu_usage = (data['core_cpu'].map(&:to_i).reduce(:+).to_f / data['core_cpu'].size).round(2)
data['cpu_usage'] = "#{cpu_usage}"

usage_string = "CPU #{data['cpu_usage']}% used"

if cpu_usage > options[:crit]
  puts "CRITICAL - #{usage_string} | #{perfdata data}"
  exit STATE_CRITICAL
elsif cpu_usage > options[:warn]
  puts "WARNING - #{usage_string} | #{perfdata data}"
  exit STATE_WARNING
else
  puts "OK - #{usage_string} | #{perfdata data}"
  exit STATE_OK
end