#!/bin/env ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)

def parse_options
  options = {}
  
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

data = retrieve_data '1.3.6.1.4.1.32473.8.1.101', parse_options

if data['state']=='PASSED'
  puts "OK - PASSED | #{perfdata data}"
  exit STATE_OK
else
  puts "CRITICAL - #{data['state']} | #{perfdata data}"
  exit STATE_CRITICAL
end
