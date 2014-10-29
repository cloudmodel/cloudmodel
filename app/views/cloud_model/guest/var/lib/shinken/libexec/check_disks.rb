#!/bin/env ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)

def parse_options
  options = {devices: [], warn: 80, crit: 90}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-d", "--disks DISKS", "mounted disks to check (don't set for all)") do |v|
      options[:disks] = v.split(',').map(&:strip)
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

class DfRawData
  def initialize
    @data = {}
  
    oid = '1.3.6.1.4.1.32473.104'
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
    data = {'description' => {}, 'usage' => {}}
    
    @data.each do |k,item|
      label = item.delete('label') || 'unknown'
      if options[:disks].empty? or options[:disks].include?(label)
        description = label
        label = if label == '/'
          'root'
        else
          label.sub(/^\//, '').gsub('_','__').gsub('/','_').to_sensor_name
        end
        
        data['description'][label] = description
        
        item.each do |sk, sv|
          data[sk] ||= {}
          data[sk][label] = sv
        end
        data['bytes_total'][label] = data['bytes_total'][label].to_i
        data['bytes_available'][label] = data['bytes_available'][label].to_i
        data['bytes_used'][label] = data['bytes_used'][label].to_i
        usage = 100.0 * (data['bytes_used'][label]) / data['bytes_total'][label]
        data['usage'][label] = usage.round(2)
      end
    end
    
    data
  end
end

options = parse_options
raw_data = DfRawData.new 
retrieve_raw_data '1.3.6.1.4.1.32473.104', raw_data, options
data = raw_data.to_data options

failures = []
warnings = []

if options[:disks]
  (options[:disks] - data['description'].values).each do |v|
    failures << "#{v} not mounted"
  end
end

data['usage'].each do |k,v|
  if v > options[:crit]
    failures << "#{v}% usage on #{k}" 
  elsif v > options[:warn]
    warnings << "#{v}% usage on #{k}" 
  end
end

if failures.empty?
  if warnings.empty?
    puts "OK - All VolumeGroups are fine | #{perfdata data}"
    exit STATE_OK
  else
    puts "WARNING - #{warnings * ', '} | #{perfdata data}"
    exit STATE_WARNING
  end
else
  puts "CRITICAL - #{(failures+warnings) * ', '} | #{perfdata data}"
  exit STATE_CRITICAL
end
