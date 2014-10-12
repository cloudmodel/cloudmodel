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
    opts.on("-s", "--ssl", "use https instead of http") do 
      options[:ssl] = true
    end
  end.parse!
  
  options
end

options = parse_options

begin
  raise "No Host given" unless options[:host]
  
  data = {}
  uri = URI("http#{options[:ssl] ? 's' : ''}://#{options[:host]}/nginx_status")
rescue Exception => e
   puts "WARNING - #{e} | #{perfdata data}"
   exit STATE_WARNING
end

begin
  res = Net::HTTP.get_response(uri)

rescue Exception => e
   puts "CRITICAL - #{e} | "
   exit STATE_CRITICAL
end
  
begin  
  data['http_version'] = res.http_version
  data['active'] = res.body.lines[0].gsub('Active connections: ', '').to_i
  data['accepted'], data['handled'], data['requests'] = res.body.lines[2].strip.split(' ').map(&:to_i)

  res.body.lines[3].gsub(/\W*:\W*/, ':').split(' ').each do |pair|
    k,v = pair.split ':'
    data["#{k.downcase}"] = v
  end
rescue Exception => e
   puts "WARNING - #{e} | #{perfdata data}"
   exit STATE_WARNING
end

if res.code == '404'
  puts "WARNING - nginx_status not found on server, but server running | "
  exit STATE_WARNING
end
if res.code == '403'
  puts "WARNING - no privileges to access nginx_status on server | "
  exit STATE_WARNING
end

# TODO: Implement checks on different values from nginx info
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