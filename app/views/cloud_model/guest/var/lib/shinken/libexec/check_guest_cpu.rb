#!/usr/bin/ruby

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
    opts.on("-g", "--guest NAME", "name of guest") do |v|
      options[:guest] = v
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

data = guest_data options

data = {
  'cpu_usage' => data['cpu_usage']
}

cpu_usage = data['cpu_usage'].to_f 
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
