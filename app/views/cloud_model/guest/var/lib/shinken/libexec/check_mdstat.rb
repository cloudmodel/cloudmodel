#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)

def parse_options
  options = {devices: []}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-d", "--devices DEVICES", "md devices to check (don't set for all)") do |v|
      options[:devices] = v.split(',').map(&:strip)
    end
  end.parse!
  
  options
end

class MdRawData
  def initialize
    @data = {}
  
    oid = '1.3.6.1.4.1.32473.102'
    @value_labels = {}
    @label_filter = /#{oid}\.1\.([0-9]+)\.1/
    @value_label_filter = /#{oid}\.0\.1\.2\.([0-9]+)/
    @value_filter = /#{oid}\.1\.([0-9]+)\.2\.([0-9]+)/
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
  end

  def to_data options
    data = {}
    
    @data.each do |k,item|
      label = item.delete('label') || 'unknown'
      if options[:devices].empty? or options[:devices].include?(label)
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
raw_data = MdRawData.new 
retrieve_raw_data '1.3.6.1.4.1.32473.102', raw_data, options
data = raw_data.to_data options

failures = []

if options[:devices]
  (options[:devices] - data['failed_devices'].keys).each do |v|
    failures << "#{v} not found"
  end
end

data['failed_devices'].each do |k,v|
  failures = "#{v} failures on #{k}" if v.to_i > 0
end

if failures.empty?
  puts "OK - All RAID arrays are without failures | #{perfdata data}"
  exit STATE_OK
else
  puts "CRITICAL - #{failures * ', '} | #{perfdata data}"
  exit STATE_CRITICAL
end
