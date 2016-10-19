#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../check_mk_helpers', __FILE__)

def parse_options
  options = {warn: [70,60,50], crit: [90,80,70]}

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-w", "--warn WARNING", "warning level in percent") do |v|
      values = v.split(',')
      options[:warn] = values.map(&:to_f)
    end
    opts.on("-c", "--crit CRITICAL", "critical level in percent") do |v|
      values = v.split(',')
      options[:crit] = values.map(&:to_f)
    end
  end.parse!
  
  options
end

def calc_usage base, data
  age = base[0].to_i - data[0].to_i
  cpus = data[1].size
  
  result = {'usage' => 0, 'usage_by_cpu' => []}
  
  data[1].each.with_index do |d,i|
    used = base[1][i].to_i - d.to_i
    result['usage_by_cpu'][i] = (100.0 * used / age).round(4)
  end
  
  result["usage"] = (result["usage_by_cpu"].inject(0, :+) / cpus).round(2)
  
  result
end

def parse_cgroup_cpu data
  result = {}
  
  lines = data.lines.to_a
  
  base = lines.shift
  base_ts, *base_usage = base.split(' ')
  
  raw = {}
  lines.reverse.each do |line|
    ts,*usage = line.split(' ')
    
    age = 1.0*(base_ts.to_i - ts.to_i)/1000000000
        
    if age <= 15 * 60
      raw[15] = [ts, usage]
    end
    if age <= 5 * 60
      raw[5] = [ts, usage]
    end
    if age <= 1 * 60
      raw[1] = [ts, usage]
    end
  end
  
  result = {}
  
  result['cpus'] = raw[1][1].size
  
  result['1_min'] = calc_usage [base_ts, base_usage], raw[1]
  result['5_min'] = calc_usage [base_ts, base_usage], raw[5]
  result['15_min'] = calc_usage [base_ts, base_usage], raw[15]  
  result
end

options = parse_options

check_mk_result = query_check_mk(options[:host])
result = filter_check_mk(check_mk_result, 'cgroup_cpu')
data = parse_cgroup_cpu result

usage = [data['1_min']["usage"], data['5_min']["usage"], data['15_min']["usage"]]

minutes = [1,5,15]
crit = []
warn = []

usage.each.with_index do |v,i|
  if v > options[:crit][i]
    crit << i
  elsif v > options[:warn][i]
    warn << i
  end
end

if not crit.empty?
  usage_array = []
  
  crit.each do |i|
    usage_array << "#{minutes[i]} min: #{usage[i]}%"
  end

  puts "CRITICAL - Usage #{usage_array * ', '} | #{perfdata data, options}"
  exit STATE_CRITICAL
elsif not warn.empty?
  usage_array = []
  
  warn.each do |i|
    usage_array << "#{minutes[i]} min: #{usage[i]}%"
  end

  puts "WARNING - Usage #{usage_array * ', '} | #{perfdata data, options}"
  exit STATE_WARNING
else
  usage_string = "Usage 1 min: #{usage[0]}%, 5 min: #{usage[1]}%, 15 min: #{usage[2]}%"

  puts "OK - #{usage_string} | #{perfdata data, options}"
  exit STATE_OK
end