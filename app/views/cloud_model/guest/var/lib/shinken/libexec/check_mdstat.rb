#!/usr/bin/ruby

require 'optparse'
require File.expand_path('../check_mk_helpers', __FILE__)

def parse_options
  options = {devices: []}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-h", "--host ADDRESS", "address to SNMP server") do |v|
      options[:host] = v
    end
    opts.on("-d", "--devices DEVICES", "md devices to check (don't set for all)") do |v|
      options[:devices] = v.split(',').map(&:strip)
    end
  end.parse!
  
  options
end

def parse_md data
  result = {
    'devs' => {},
    'sections' => {}
  }
  lines = data.lines
  personalities = lines.shift # first line contains raid personalities of md
  result['sections']['personalities'] = personalities.scan(/\[([^\[]*)\]/).flatten
  
  dev = nil
  line_no = 0
  
  lines.each do |line|
    line_no += 1
    if dev.nil?
      dev, tail = line.split ' : '
      if tail
        result['devs'][dev] = {}
        line = tail
      else
        sec, tail = line.split ': '
        result['sections'][sec] = tail.strip
        line_no = 0
      end
    end
    
    if line.nil? or line.strip.empty?    
      dev = nil
      line_no = 0
    end
    
    if line_no == 1
      state, personality, *devices = line.strip.split(' ')
      
      result['devs'][dev]['state'] = state
      result['devs'][dev]['personality'] = personality
      result['devs'][dev]['devices'] = devices*';'
    end
    
    if line_no == 2 and result['devs'][dev]['personality'] == 'raid1'
      # 2896447807 blocks super 1.2 [2/2] [UU]
      blocks, null, persistance, version, devs, *dev_state = line.strip.split(' ')
      
      result['devs'][dev]['array_size'] = blocks
      result['devs'][dev]['version'] = version
      result['devs'][dev]['persistance'] = persistance == 'super' ? 'Superblock is persistent' : persistance
      result['devs'][dev]['dev_state'] = dev_state * " "
      
      active_devices, null, total_devices = devs.scan(/[([0-9]*)\/([0-9]*)]/)
      result['devs'][dev]['active_devices'] = active_devices
      result['devs'][dev]['total_devices'] = total_devices
    end
  end

  result
end

def perfdata_md data
  pdata = {}
  
  data['devs'].each do |k,v|
    v.each do |vk, vv|
      pdata[vk] ||= {}
      pdata[vk][k] = vv
    end
  end
  
  perfdata pdata
end

options = parse_options

check_mk_result = query_check_mk(options[:host])
result = filter_check_mk(check_mk_result, 'md')
data = parse_md result


failures = []

if options[:devices]  
  (options[:devices] - data['devs'].keys).each do |v|
    failures << "#{v} not found"
  end
end

data['devs'].each do |k,v|
  if v['state'] != 'active'
    failures << "#{k} not active"
  end
end

if failures.empty?
  puts "OK - All RAID arrays are without failures | #{perfdata_md data}"
  exit STATE_OK
else
  puts "CRITICAL - #{failures * ', '} | #{perfdata_md data}"
  exit STATE_CRITICAL
end
