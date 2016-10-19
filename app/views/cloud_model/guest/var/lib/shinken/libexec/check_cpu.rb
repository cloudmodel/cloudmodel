#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../check_mk_helpers', __FILE__)
require 'net/http'

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

def parse_cpu_uptime cpu_data, uptime_data
  data = {}
  cpu_data = cpu_data.split ' '
  uptime_data = uptime_data.split ' '
  
  data[:load_1_min] = cpu_data[0].to_f
  data[:load_5_min] = cpu_data[1].to_f
  data[:load_15_min] = cpu_data[2].to_f
  data[:cpus] = cpu_data[5].to_i
  data[:uptime] = uptime_data[0]
  data[:uptime_idle] = uptime_data[1]
  
  proc = cpu_data[3].split('/')
  data[:processes] = proc[1]
  data[:running_processes] = proc[0]
  
  data
end

options = parse_options

begin
  raise "No Host given" unless options[:host]
  
  data={}
rescue Exception => e
  puts "WARNING - #{e} | #{perfdata data, options}"
  exit STATE_WARNING
end

check_mk_result = query_check_mk(options[:host])
cpu_result = filter_check_mk(check_mk_result, 'cpu')
uptime_result = filter_check_mk(check_mk_result, 'uptime')

data = parse_cpu_uptime cpu_result, uptime_result
usage = [data[:load_1_min], data[:load_5_min], data[:load_15_min]].map{|v| v / data[:cpus]}

minutes = [1,5,15]
crit = []
warn = []

usage.each.with_index do |v,i|
  
  if v*100 > options[:crit][i]
    crit << i
  elsif v*100 > options[:warn][i]
    warn << i
  end
end


if not crit.empty?
  usage_array = []
  
  crit.each do |i|
    usage_array << "#{minutes[i]} min: #{usage[i] * 100}%"
  end

  puts "CRITICAL - Usage #{usage_array * ', '} | #{perfdata data, options}"
  exit STATE_CRITICAL
elsif not warn.empty?
  usage_array = []
  
  warn.each do |i|
    usage_array << "#{minutes[i]} min: #{usage[i] * 100}%"
  end

  puts "WARNING - Usage #{usage_array * ', '} | #{perfdata data, options}"
  exit STATE_WARNING
else
  usage_string = "Usage 1 min: #{usage[0] * 100}%, 5 min: #{usage[1] * 100}%, 15 min: #{usage[2] * 100}%"

  puts "OK - #{usage_string} | #{perfdata data, options}"
  exit STATE_OK
end