#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../shinken_helpers', __FILE__)
require 'mongo'

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

def unbson in_data
  out_data = {}
  in_data.each do |k,v|
    if v.class == BSON::OrderedHash
      out_data[k]= unbson v
    else
      out_data[k]=v
    end
  end
  out_data
end

options = parse_options

begin
  raise "No Host given" unless options[:host]
  
  data = {}
  
  mongo_client = Mongo::MongoClient.new(options[:host], 27017)
  data = mongo_client.db.command('serverStatus' => true)
rescue Mongo::ConnectionFailure => e
  puts "CRITICAL - #{e} | #{perfdata data}"
  exit STATE_CRITICAL
rescue Exception => e
   puts "WARNING - #{e} | #{perfdata data}"
   exit STATE_WARNING
end


# Remove keys containing config details and doubled values
%w(host process pid uptimeMillis uptimeEstimate localTime ).each do |k|
  data.delete(k)
end

begin
  data['backgroundFlushing'].delete('last_finished')
rescue
end
  
data = unbson data

# TODO: Implement checks on different values from mongo status

puts "OK | #{perfdata data}"
exit STATE_OK