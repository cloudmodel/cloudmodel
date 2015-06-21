#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../snmp_helpers', __FILE__)
require 'net/http'
require 'openssl'
require 'nokogiri'

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
  
  data = {}
  uri = URI("http#{options[:ssl] ? 's' : ''}://#{options[:host]}:8080/manager/status?XML=true")
rescue Exception => e
   puts "WARNING - #{e} | #{perfdata data}"
   exit STATE_WARNING
end

begin
  res = nil
  
  Net::HTTP.start(uri.host, uri.port,
    :use_ssl => uri.scheme == 'https', 
    :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

    req = Net::HTTP::Get.new uri.request_uri
    req.basic_auth 'mon', 'mon'

    res = http.request req 
  end
rescue Exception => e
   puts "CRITICAL - #{e} | "
   exit STATE_CRITICAL
end
  
data['http_version'] = res.http_version

if res.code == '404'
  puts "WARNING - tomcat status not found on server, but server running | "
  exit STATE_WARNING
end
if res.code == '401'
  puts "WARNING - no privileges to access tomcat status on server | "
  exit STATE_WARNING
end

begin
  doc = Nokogiri::XML(res.body)
  doc.xpath('//status/jvm/memory').first.attributes.each do |k,v| 
    data["memory_#{k}"] = v.to_s.to_i
  end
  
  if data['memory_free'] and data['memory_total'] > 0
    mem_usage = (100.0 * (data['memory_total']-data['memory_free'])/data['memory_total'])
    data['memory_usage'] = mem_usage.round(2)
  end
  
  connector = doc.xpath('//status/connector[@name=\'"http-nio-8080"\']')
  if connector.size == 0
    connector = doc.xpath('//status/connector[@name=\'"http-bio-8080"\']')    
  end
  if connector.size > 0
    connector.xpath('./requestInfo').first.attributes.each do |k,v| 
      data["request_#{k}"] = v.to_s.to_i
    end
    connector.xpath('./threadInfo').first.attributes.each do |k,v| 
      data["thread_#{k.gsub('Thread', '')}"] = v.to_s.to_i
    end
    
    thread_usage = (100.0 * data['thread_currentCount']/data['thread_maxs'])
    data['thread_usage'] = thread_usage.round(2)
  end
rescue Exception => e
  puts "WARNING - could not parse status xml: #{e} | #{perfdata data}"
  exit STATE_WARNING
end

usage_string = "Memory #{data['memory_usage']}% used; Threads #{data['thread_usage']}% used"

if mem_usage > options[:crit] or thread_usage > options[:crit]
  puts "CRITICAL - #{usage_string} | #{perfdata data}"
  exit STATE_CRITICAL
elsif mem_usage > options[:warn] or thread_usage > options[:warn]
  puts "WARNING - #{usage_string} | #{perfdata data}"
  exit STATE_WARNING
else
  puts "OK - #{usage_string} | #{perfdata data}"
  exit STATE_OK
end