#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../check_mk_helpers', __FILE__)

def parse_options
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-d", "--drives DRIVES", "drives to check (don't set for all)") do |v|
      options[:drives] = v.split(',').map(&:strip) if v
    end
  end.parse!
  
  options
end

def parse_smart data
  result = {}
  dev = nil
  
  data.lines.each do |line|
    if line[0] == "["
      dev = line.strip.gsub(/\[\/dev\/(.*)\]/, '\1')
    else
      k,v = line.split(':').map(&:strip)
      k = k.underscore
      
      result[k] ||= {}
      result[k][dev] = v ? v.split(' ').first : '-'
    end
  end
  
  result
end

options = parse_options

check_mk_result = query_check_mk(options[:host])
result = filter_check_mk(check_mk_result, 'smart')
data = parse_smart result

failures = []
if options[:drives]
  (options[:drives] - data['smart_status'].keys).each do |v|
    failures << "#{v} not found"
  end
end

data['smart_status'].each do |k,v|
  failures << "Test on #{k} not passed (#{v})" unless v.to_s == 'PASSED'
end

if failures.empty?
  puts "OK - All disks passed smart tests | #{perfdata data}"
  exit STATE_OK
else
  failure_string = failures * ', '
  puts "CRITICAL - #{failure_string} | #{perfdata data}"
  exit STATE_CRITICAL
end