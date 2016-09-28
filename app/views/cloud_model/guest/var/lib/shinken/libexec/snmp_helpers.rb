require File.expand_path('../shinken_helpers', __FILE__)
require 'snmp'

def snmpdata_to_hash(data)
  hash = {}
  data.split(' ').each do |pair|
    name, value = pair.split('=')
    hash[name]=value
  end
  hash
end

def perfdata(data, options = {})
  prefix = options[:prefix] || ''
  
  if data
    data.map do |k,v| 
      if v.class == Array
        counter = 0
        v.map do |sv|
          counter += 1
          "#{prefix}#{k.to_sensor_name}_#{counter}=#{sv}"
        end * ', '
      elsif v.class == Hash
        perfdata v, prefix: "#{prefix}#{k.to_sensor_name}_"
      else
        "#{prefix}#{k.to_sensor_name}=#{v}"
      end
    end * ', '
  end
end

def retrieve_data oid, options
  data = {}
  begin
    raise "No Host given" unless options[:host]
    raise "No Device given" unless options[:dev]
  
    SNMP::Manager.open(host: options[:host]) do |manager|
      response = manager.walk([SNMP::ObjectId.new(oid)]) do |row|
        row.each do |vb|
          data = snmpdata_to_hash(vb.value)
        
          if data.delete('dev') == options[:dev]
            return data 
          end
        end
    	end
    end
    raise "Device '#{options[:dev]}' not found"
  rescue Exception => e
    puts "WARNING - #{e} | "
    exit STATE_WARNING
  end
end

def retrieve_data_from_oids oids, options
  data = {}
  
  begin
    raise "No Host given" unless options[:host]
    
    SNMP::Manager.open(host: options[:host], mib_modules: []) do |manager|
      response = manager.get(oids.keys)

      response.each_varbind do |vb|
        data[oids[vb.oid.to_s].to_s.to_sensor_name] = vb.value
      end
    end
  rescue Exception => e
    puts "WARNING - #{e} | "
    exit STATE_WARNING
  end 
  
  return data
end

def retrieve_data_from_oid_multi_to label, oid, options
  data = {}
  
  begin
    raise "No Host given" unless options[:host]
    
    label = label.to_sensor_name
    data["#{label}"] = []
    SNMP::Manager.open(host: options[:host]) do |manager|
      response = manager.walk([SNMP::ObjectId.new(oid)]) do |row|
        data["#{label}"] << row.first.value
    	end
    end
  rescue Exception => e
    puts "WARNING - #{e} | "
    exit STATE_WARNING
  end
  
  return data
end

def retrieve_raw_data oid, raw_data, options
  begin
    raise "No Host given" unless options[:host]
  
    SNMP::Manager.open(host: options[:host], mib_modules: []) do |manager|
      response = manager.walk([SNMP::ObjectId.new(oid)]) do |row|  
        row.each do |item|
          raw_data << item
        end
    	end
    end  
  rescue Exception => e
    #$stderr.puts e.backtrace
    puts "WARNING - #{e} | "
    exit STATE_WARNING
  end
end

class GuestRawData
  def initialize
    @data = {}
  
    oid = '1.3.6.1.4.1.32473.100.1'
    @label_filter = /#{oid}.([0-9]+)\.1/
    @mem_available_filter = /#{oid}.([0-9]+)\.2\.1/
    @mem_used_filter = /#{oid}.([0-9]+)\.2\.2/
    @cpu_usage_filter = /#{oid}.([0-9]+)\.3\.1/
  end
  
  def insert index, data_type, value
  
    @data[index] ||= {}
    @data[index][data_type] = value
  end

  def << item
    name = item.name.to_s
    value = item.value
  
    if res = @label_filter.match(name)
      insert res[1], 'label', value
    end
    if res = @mem_available_filter.match(name)
      insert res[1], 'mem_total', value
    end
    if res = @mem_used_filter.match(name)
      insert res[1], 'mem_used', value
    end
    if res = @cpu_usage_filter.match(name)
      insert res[1], 'cpu_usage', value
    end
  end

  def to_data
    data = {}
    @data.each do |k,item|
      label = item.delete('label') || 'unknown'
      data[label.to_s] = item
    end
    data
  end
end

def guest_data options

  raw_data = GuestRawData.new 
  
  retrieve_raw_data '1.3.6.1.4.1.32473.100.1', raw_data, options

  data = raw_data.to_data

  begin
    raise "No Guest given" unless options[:guest]
    unless data[options[:guest]]
      raise "Guest '#{options[:guest]}' not found"
    end
  rescue Exception => e
    puts "WARNING - #{e} | "
    exit STATE_WARNING
  end

  data[options[:guest]] 
end