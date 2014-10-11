#!/bin/env ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)
require 'redis'

def parse_options
  options = {warn: 80, crit: 90}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
  end.parse!
  
  options
end

options = parse_options

begin
  raise "No Host given" unless options[:host]
  
  data = {}
  redis = Redis.new(host: options[:host], port: 6379, db: 0)

  data = redis.info
rescue Redis::CannotConnectError => e
  puts "CRITICAL - #{e} | #{perfdata data}"
  exit STATE_CRITICAL
rescue Exception => e
   puts "WARNING - #{e} | #{perfdata data}"
   exit STATE_WARNING
end

# Remove keys containing config details and doubled values
%w(redis_version redis_git_sha1 redis_mode config_file mem_allocator redis_build_id os arch_bits multiplexing_api gcc_version process_id run_id used_memory_human used_memory_peak_human ).each do |k|
  data.delete(k)
end

# TODO: Implement checks on different values from redis info
#
# usage = 95
#
# if usage > options[:crit]
#   puts "CRITICAL - #{data['usage']} use | #{perfdata data}"
#   exit STATE_CRITICAL
# elsif usage > options[:warn]
#   puts "WARNING - #{data['usage']} used | #{perfdata data}"
#   exit STATE_WARNING
# else
#   puts "OK - #{data['usage']} used | #{perfdata data}"
#   exit STATE_OK
# end

puts "OK | #{perfdata data}"
exit STATE_OK