require 'snmp'

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

def snmpdata_to_hash(data)
  hash = {}
  data.split(' ').each do |pair|
    name, value = pair.split('=')
    hash[name]=value
  end
  hash
end

def perfdata(data)
  if data
    data.map{|k,v| "#{k.gsub('-','_')}=#{v}"} * ', '
  end
end

def retrieve_data oid, options
  data = {}
  begin
    raise "No Host given" unless options[:host]
    raise "No Device given" unless options[:dev]
  
    SNMP::Manager.open(:host => options[:host]) do |manager|
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
    puts "WARNING: #{e} | #{perfdata data}"
    exit STATE_WARNING
  end
end