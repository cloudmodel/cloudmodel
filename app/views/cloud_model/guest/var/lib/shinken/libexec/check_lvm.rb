#!/bin/env ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)

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
data = retrieve_data '1.3.6.1.4.1.32473.8.3.101', options

size = data['vsize'].to_i
free = data['vfree'].to_i
usage = 100.0 * (size - free) / size
data = {'usage' => "#{usage.round(2)}%"}.merge data

if usage > options[:crit]
  puts "CRITICAL - #{data['usage']} use | #{perfdata data}"
  exit STATE_CRITICAL
elsif usage > options[:warn]  
  puts "WARNING - #{data['usage']} used | #{perfdata data}"
  exit STATE_WARNING
else
  puts "OK - #{data['usage']} used | #{perfdata data}"
  exit STATE_OK
end
