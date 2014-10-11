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
  end.parse!
  
  options
end

options = parse_options

oid = '1.3.6.1.4.1.2021.13.16'

class RawData
  def initialize
    @data = {}
    
    oid = '1.3.6.1.4.1.2021.13.16'
    @label_filter = /#{oid}.(.+)\.1\.2\.(.+)/
    @value_filter = /#{oid}.(.+)\.1\.3\.(.+)/
  end
  
  def snmp_type_from_id id
    {
      '2' => 'temp',
      '3' => 'fan',
      '4' => 'volt',
      '5' => 'misc'
    }[id] || "unknown_#{id}"
  end
  
  def transform_data snmp_type, value
    case snmp_type 
      when 'temp'
        if value.to_i > 100000000
          "#{value.to_f/100000000}"
        else
          "#{value.to_f/1000}"
        end
      when 'fan'
        "#{value.to_i}"
      when 'volt'
        "#{value.to_f/1000}"
      else 
        value
    end
  end
  
  def insert snmp_type_id, index, data_type, value
    snmp_type = snmp_type_from_id(snmp_type_id)
    
    @data[snmp_type] ||= {}
    @data[snmp_type][index] ||= {}
    @data[snmp_type][index][data_type] = value
  end
  
  def << item
    name = item.name.to_s
    value = item.value
    
    if res = @label_filter.match(name)
      insert res[1], res[2], 'label', value
    end
    if res = @value_filter.match(name)
      insert res[1], res[2], 'value', value
    end
  end
  
  def to_data
    data = {}
    @data.each do |snmp_type, items|
      items.values.each do |item|
        data["#{snmp_type}_#{item['label'].to_sensor_name}"] = transform_data(snmp_type, item['value'])
      end
    end
    data
  end
end

raw_data = RawData.new 
  
retrieve_raw_data oid, raw_data, options

puts "OK - OK | #{perfdata raw_data.to_data}"
exit STATE_OK
  