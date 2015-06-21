#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)

def parse_options
  options = {drives: []}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-d", "--drives DRIVES", "drives to check (don't set for all)") do |v|
      options[:drives] = v.split(',').map(&:strip)
    end
  end.parse!
  
  options
end

class SmartRawData
  def initialize
    @data = {}
  
    oid = '1.3.6.1.4.1.32473.101'
    @value_labels = {}
    @label_filter = /#{oid}\.1\.([0-9]+)\.1/
    @value_label_filter = /#{oid}\.0\.1\.2\.2\.([0-9]+)/
    @value_filter = /#{oid}\.1\.([0-9]+)\.2\.2\.([0-9]+)/
    @status_value_filter = /#{oid}\.1\.([0-9]+)\.2\.1/
  end
  
  def insert index, data_type, value
  
    @data[index] ||= {}
    @data[index][data_type] = value
  end

  def << item
    name = item.name.to_s
    value = item.value
  
    if res = @label_filter.match(name)
      insert res[1], 'label', value
    end
    if res = @value_label_filter.match(name)
      @value_labels[res[1]] = value.to_s.underscore
    end
    if res = @value_filter.match(name)
      insert res[1], @value_labels[res[2]], value
    end
    if res = @status_value_filter.match(name)
      insert res[1], 'smart_status', value
    end
  end

  def to_data options
    data = {}
    
    @data.each do |k,item|
      label = item.delete('label') || 'unknown'
      if options[:drives].empty? or options[:drives].include?(label)
        item.each do |sk, sv|
          data[sk] ||= {}
          data[sk][label] = sv
        end
      end
    end
    data
  end
end

options = parse_options
raw_data = SmartRawData.new 
retrieve_raw_data '1.3.6.1.4.1.32473.101', raw_data, options
data = raw_data.to_data options

failures = []
if options[:drives]
  (options[:drives] - data['smart_status'].keys).each do |v|
    failures << "#{v} not found"
  end
end

data['smart_status'].each do |k,v|
  failures << "Test on #{k} not passed" unless v.to_s == 'PASSED'
end

if failures.empty?
  puts "OK - All disks passed smart tests | #{perfdata data}"
  exit STATE_OK
else
  failure_string = failures * ', '
  puts "CRITICAL - #{failure_string} | #{perfdata data}"
  exit STATE_CRITICAL
end


# data = retrieve_data '1.3.6.1.4.1.32473.8.1.101', parse_options
#
# if data['state']=='PASSED'
#   puts "OK - PASSED | #{perfdata data}"
#   exit STATE_OK
# else
#   puts "CRITICAL - #{data['state']} | #{perfdata data}"
#   exit STATE_CRITICAL
# end
