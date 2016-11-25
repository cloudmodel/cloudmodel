#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../shinken_helpers', __FILE__)
require 'net/http'
require 'openssl'
require 'json'
require 'time'

require 'yaml'

def parse_options
  options = {warn: 80, crit: 90}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SOLR server") do |v|
      options[:host] = v
    end
    opts.on("-s", "--ssl", "use https instead of http") do 
      options[:ssl] = true
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

def read_json uri
  begin
    res = nil
  
    Net::HTTP.start(uri.host, uri.port,
      :use_ssl => uri.scheme == 'https', 
      :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

      req = Net::HTTP::Get.new uri.request_uri
      res = http.request req 
    end
  rescue Exception => e
     puts "CRITICAL - #{e} | "
     exit STATE_CRITICAL
  end
  
#  data['http_version'] = res.http_version

  if res.code == '404'
    puts "WARNING - solr status not found on server, but server running | "
    exit STATE_WARNING
  end
  if res.code == '401'
    puts "WARNING - no privileges to access solr status on server | "
    exit STATE_WARNING
  end

  begin
    status = JSON.parse(res.body)
  rescue
    puts "WARNING - can't parse solr json | "
    exit STATE_WARNING
  end
end

options = parse_options

base_url = "http#{options[:ssl] ? 's' : ''}://#{options[:host]}:8080/solr/admin"

begin
  raise "No Host given" unless options[:host]
  
  data = {}
  status_uri = URI("#{base_url}/info/system?wt=json")
  cores_uri = URI("#{base_url}/cores?wt=json")
rescue Exception => e
   puts "WARNING - #{e} | #{perfdata data}"
   exit STATE_WARNING
end

status = read_json status_uri
cores = read_json cores_uri

begin
  solr_start_at = Time.parse status['jvm']['jmx']['startTime']
  core_start_at = if cores['status'].empty?
    Time.now
  else
    Time.parse cores['status'].values.first['startTime']
  end
  
  data['core_start_time'] = core_start_at - solr_start_at
rescue
end

begin  
  data['memory_free'] = status['jvm']['memory']['raw']['free']
  data['memory_total'] = status['jvm']['memory']['raw']['total']
  mem_usage = data['memory_usage'] = status['jvm']['memory']['raw']['used%']
  data['cores_running'] = cores['status'].count
  
  #puts cores.to_yaml
rescue Exception => e
  puts "WARNING - could not parse status json: #{e} | #{perfdata data}"
  exit STATE_WARNING
end

usage_string = "Memory #{'%.2f' % mem_usage}% used"

if data['cores_running'] == 0
  puts "CRITICAL - No core running after #{'%.1f' % data['core_start_time']}s| #{perfdata data}"
  exit STATE_CRITICAL
end

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