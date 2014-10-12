#!/bin/env ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)

def parse_options
  options = {crit: 90, warn: 95, disks: []}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-d", "--disks DISKS", "disks to check (don't set for all)") do |v|
      options[:disks] = v.split(',').map(&:strip)
    end
    opts.on("-b", "--base PREFIX", "base prefix for mountpoints of disks to check") do |v|
      options[:base] = v
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

class RawData
  def initialize options={}
    @options = options
    @data = {}
    @base_oid = '1.3.6.1.2.1.25.2.3.1'
  end
  
  def storage_type_from_id id
    id = id.to_s.gsub('1.3.6.1.2.1.25.2.1.', '')
    
    {
      '1'  => 'other',
      '2'  => 'ram',
      '3'  => 'virtual_memory',
      '4'  => 'fixed_disk',
      '5'  => 'removable_disk',
      '6'  => 'floppy_disk',
      '7'  => 'compact_disk',
      '8'  => 'ram_disk',
      '9'  => 'flash_memory',
      '10' => 'network_disk'
    }[id] || "unknown_#{id}"
  end
  
  def data_type_from_id id
    {
      '1'  => 'index',
      '2'  => 'type',
      '3'  => 'description',
      '4'  => 'allocation_units',
      '5'  => 'size',
      '6'  => 'used',
      '7'  => 'allow_failures'
    }[id] || "unknown_#{id}"
  end
  
  def insert index, data_type, value    
    @data[index] ||= {}
    @data[index][data_type] = value
  end
  
  def << item
    name = item.name.to_s.gsub(/^#{@base_oid}\./, '')
    value = item.value
    
    data_type, index = name.split('.')
    
    case data_type
    when '1'
      nil
    when '2'
      insert index, data_type_from_id(data_type), storage_type_from_id(value)
    else
      insert index, data_type_from_id(data_type), value
    end
  end
  
  def to_data
    data = {
      'description' => {},
      'size' => {}, 
      'used' => {},
      'usage' => {}
    }
    
    real_disks = @options[:disks].map{ |d| "#{@options[:base]}#{d}".gsub(/\/$/, '').gsub(/^$/, '/') }
    
    @data.values.each do |item|
      item_description = item['description'].sub(/#{@options[:base]}/, '').sub(/^$/, '/')
      
      item_sensor = if item_description == '/'
        'root'
      else
        item_description.sub(/^\//, '').gsub('_','__').gsub('/','_').to_sensor_name
      end
      
      if %w(fixed_disk removable_disk).include? item['type']
        if (real_disks.empty? and item['description'].match(/^#{@options[:base]}/)) or real_disks.include?(item['description'])
          data['description'][item_sensor] = item_description
          %w(size used).each do |data_type|
            data[data_type]["#{item_sensor}_kb"] = (1.0 * item[data_type].to_i * item['allocation_units'].to_i / 1024).round(3)
          end
          item_usage = (100.0 * item['used'].to_i / item['size'].to_i).round(2)
          data['usage']["#{item_sensor}"] = item_usage
        end
      end
    end
    
    data
  end
end

options = parse_options
oid = '1.3.6.1.2.1.25.2.3.1'
raw_data = RawData.new options
  
retrieve_raw_data oid, raw_data, options

data = raw_data.to_data 

max_usage = 0.0
max_item = '<unknown>'
data['usage'].each do |k,v|
  if v > max_usage
    max_usage = v
    max_item = k
  end
end

usage_string = "Highest usage #{max_usage}% appears on #{data['description'][max_item]}"

if max_usage > options[:crit]
  puts "CRITICAL - #{usage_string} | #{perfdata data}"
  exit STATE_CRITICAL
elsif max_usage > options[:warn]
  puts "WARNING - #{usage_string} | #{perfdata data}"
  exit STATE_WARNING
else
  puts "OK - #{usage_string} | #{perfdata data}"
  exit STATE_OK
end
