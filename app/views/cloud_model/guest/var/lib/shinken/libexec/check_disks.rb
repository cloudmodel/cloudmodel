#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../check_mk_helpers', __FILE__)

def parse_options
  options = {disks: [], warn: 80, crit: 90}
  
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

def parse_df data
  result = {}
  mode = ""
  
  data.lines.each do |line|
    mode = "_inodes" if line.strip == '[df_inodes_start]'
        
    line_data = line.split ' '
    
    if mount_name = line_data[6]
      result[mount_name] ||= {}
      result[mount_name]["device"] = line_data[0]
      result[mount_name]["fs"] = line_data[1]
      total = result[mount_name]["total#{mode}"] = line_data[2].to_i
      used = result[mount_name]["used#{mode}"] = line_data[3].to_i
      result[mount_name]["available#{mode}"] = line_data[4].to_i
      result[mount_name]["iusage#{mode}"] = line_data[5].to_i
      result[mount_name]["usage#{mode}"] = (100.0 * used / total).round(2)
    end
  end
    
  result
end

def perfdata(data, options = {})  
  out = []
  if data
    data.map do |k,v| 
      if options[:disks].empty? or options[:disks].include?(k)
        name = if k == '/'
          'root'
        else
          k.sub(/^\//, '').gsub('_','__').gsub('/','_').to_sensor_name
        end
      
        out << [
          "description_#{name}=#{k}",
          "device_#{name}=#{v['device']}",
          "usage_#{name}=#{v['usage']}",
          "total_#{name}=#{v['total']}",
          "available_#{name}=#{v['available']}",
          "usage_inodes_#{name}=#{v['usage_inodes']}",
          "total_inodes_#{name}=#{v['total_inodes']}",
          "available_inodes_#{name}=#{v['available_inodes']}"
        ] * ', '
      end
    end 
    out * ', '
  end
end

options = parse_options

failures = []
warnings = []

check_mk_result = query_check_mk(options[:host])
result = filter_check_mk(check_mk_result, 'df')

data = parse_df result

unless options[:disks].empty?
  (options[:disks] - data.keys).each do |v|
    failures << "#{v} not mounted"
  end
end

max_usage = 0.0
max_item = '<unknown>'

data.each do |k,v|
  if v["usage"] > options[:crit]
    failures << "#{v["usage"]}% usage on #{k}" 
  elsif v["usage"] > options[:warn]
    warnings << "#{v["usage"]}% usage on #{k}" 
  end
  if v["usage"] > max_usage
    max_usage = v["usage"]
    max_item = k
  end
end

if failures.empty?
  if warnings.empty?
    usage_string = "Highest usage #{max_usage}% on #{max_item}"
    
    puts "OK - #{usage_string} | #{perfdata data, options}"
    exit STATE_OK
  else
    puts "WARNING - #{warnings * ', '} | #{perfdata data, options}"
    exit STATE_WARNING
  end
else
  puts "CRITICAL - #{(failures+warnings) * ', '} | #{perfdata data, options}"
  exit STATE_CRITICAL
end
