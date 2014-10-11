#!/bin/env ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)
require 'net/http'

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

options = parse_options

begin
  raise "No Host given" unless options[:host]
  
  data={}


rescue Exception => e
  puts "WARNING - #{e} | #{perfdata data}"
  exit STATE_WARNING
end

data = retrieve_data_from_oids(
  {
    '1.3.6.1.4.1.2021.4.4.0'  => :swap_free,     
  	'1.3.6.1.4.1.2021.4.3.0'  => :swap_total, 
  	'1.3.6.1.4.1.2021.4.5.0'  => :mem_total, 
  	'1.3.6.1.4.1.2021.4.6.0'  => :mem_free,  
  	'1.3.6.1.4.1.2021.4.15.0' => :mem_cached,
  	'1.3.6.1.4.1.2021.4.14.0' => :mem_buffers,
    }, options
)

data['mem_used'] = data['mem_total'].to_i - data['mem_free'].to_i
mem_usage = (100.0 * data['mem_used'] / data['mem_total'].to_i).round(2)
data['mem_usage'] = "#{mem_usage}"

data['swap_used'] = data['swap_total'].to_i - data['swap_free'].to_i
swap_usage = (100.0 * data['swap_used'] / data['swap_total'].to_i).round(2)
data['swap_usage'] = "#{swap_usage}"

usage_string = "Memory #{data['mem_usage']}% used; Swap #{data['swap_usage']}% used"

if mem_usage > options[:crit] or swap_usage > options[:crit]
  puts "CRITICAL - #{usage_string} | #{perfdata data}"
  exit STATE_CRITICAL
elsif mem_usage > options[:warn] or swap_usage > options[:warn]
  puts "WARNING - #{usage_string} | #{perfdata data}"
  exit STATE_WARNING
else
  puts "OK - #{usage_string} | #{perfdata data}"
  exit STATE_OK
end