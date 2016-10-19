#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../check_mk_helpers', __FILE__)

def parse_options
  options = {warn: 80, crit: 90}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
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

def parse_cgroup_mem data
  result = {
    "mem_total" => 0,
    "mem_free" => 0,
    "mem_used" => 0,
    "mem_usage" => 0.0
  }
  replacements = {
    "limit_in_bytes" => "mem_total",
    "usage_in_bytes" => "mem_used"
  }

  data.lines.each do |line|
    k,v = line.split(' ')
    result[replacements[k] || k] = v.to_i
  end
  
  result
end

options = parse_options

check_mk_result = query_check_mk(options[:host])
result = filter_check_mk(check_mk_result, 'cgroup_mem')
data = parse_cgroup_mem result

data['mem_free'] = data['mem_total'] - data['mem_used']

mem_usage = (100.0 * (data['mem_total'].to_i - data['mem_free'].to_i) / data['mem_total'].to_i).round(2)
data['mem_usage'] = "#{mem_usage}"


usage_string = "Memory #{data['mem_usage']}% used"

if mem_usage > options[:crit]
  puts "CRITICAL - #{usage_string} | #{perfdata data}"
  exit STATE_CRITICAL
elsif mem_usage > options[:warn]
  puts "WARNING - #{usage_string} | #{perfdata data}"
  exit STATE_WARNING
else
  puts "OK - #{usage_string} | #{perfdata data}"
  exit STATE_OK
end