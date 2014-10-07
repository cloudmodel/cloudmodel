#!/bin/env ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)

def parse_options
  options = {num_devices: 2}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-n", "--num_devices INTEGER", "Number of disks that should be in this RAID") do |v|
      options[:num_devices] = v.to_i
    end
    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-d", "--device DEVICE", "device to check") do |v|
      options[:dev] = v
    end
  end.parse!
  
  options
end

options = parse_options
data = retrieve_data '1.3.6.1.4.1.32473.8.2.101', options

data = {'num_devices' => data.delete('num-devices')}.merge data

if data['num_devices'].to_i==options[:num_devices]
  puts "OK | #{perfdata data}"
  exit STATE_OK
else
  puts "CRITICAL - Expected #{options[:num_devices]} devices, found #{data['num_devices']} | #{perfdata data}"
  exit STATE_CRITICAL
end
