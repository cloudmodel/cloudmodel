#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../check_mk_helpers', __FILE__)

def parse_options
  options = {devices: nil, warn: 80, crit: 90}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-d", "--devices DEVICES", "md devices to check (don't set for all)") do |v|
      options[:devices] = v.split(',').map(&:strip)
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

def parse_vgs data
  result = {
    'usage' => {},
    'num_pv' => {},
    'num_lv' => {},
    'num_sn' => {},
    'attr' => {},
    'vsize' => {},
    'vfree' => {}
  }
  
  data.lines.each do |line|
    dev,num_pv,num_lv,num_sn,attr,vsize,vfree = line.strip.split(':')
    
    result['num_pv'][dev] = num_pv.to_i
    result['num_lv'][dev] = num_lv.to_i
    result['num_sn'][dev] = num_sn.to_i
    result['attr'][dev] = attr
    result['vsize'][dev] = vsize = vsize.to_i
    result['vfree'][dev] = vfree = vfree.to_i
    result['usage'][dev] = (100.0 * (vsize - vfree) / vsize).round(2)
  end
  
  result
end


options = parse_options

check_mk_result = query_check_mk(options[:host])
result = filter_check_mk(check_mk_result, 'lvm_vgs')
data = parse_vgs result

failures = []
warnings = []

if options[:devices]
  (options[:devices] - data['usage'].keys).each do |v|
    failures << "#{v} not found"
  end
end

max_usage = 0.0
max_item = '<unknown>'

data['usage'].each do |k,v|
  if v > options[:crit]
    failures << "#{v}% usage on #{k}" 
  elsif v > options[:warn]
    warnings << "#{v}% usage on #{k}" 
  end

  if v > max_usage
    max_usage = v
    max_item = k 
  end
end

if failures.empty?
  if warnings.empty?
    usage_string = "Highest usage #{max_usage}% on #{max_item}"
    
    puts "OK - #{usage_string} | #{perfdata data}"
    exit STATE_OK
  else
    puts "WARNING - #{warnings * ', '} | #{perfdata data}"
    exit STATE_WARNING
  end
else
  puts "CRITICAL - #{(failures+warnings) * ', '} | #{perfdata data}"
  exit STATE_CRITICAL
end
