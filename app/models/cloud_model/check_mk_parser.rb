module CloudModel
  class CheckMkParser
    
    def self.parse result
      hash = {}
      context = ''
      dev = nil
      sensors_adapter = nil
      sensor = nil
      sensor_result = nil
      lxd_yaml = ''
    
      result.lines.each do |line|
        if line[0..2] == '<<<'
          if context == 'sensors'
            if sensor
              hash['sensors'][sensor] = sensor_result
            end
          end
          
          if context == 'lxd'
            hash['lxd'] = YAML.load lxd_yaml unless lxd_yaml.blank?
          end
          
          context = line.gsub(/^<<</, '').gsub(/>>>\n$/, '')
          hash[context] = {}
        else # some data
          if hash[context]
            case context
            when 'check_mk', 'mem'
              parts = line.strip.split(':')
              key = parts.shift.underscore
              hash[context][key] = (parts * ':').strip
            when 'df'
              parts = line.strip.split(' ')
              key = parts.shift
              unless ["[df_inodes_start]", "[df_inodes_end]"].include? key
                hash[context][key] ||= {}
                hash[context][key]['mountpoint'] = parts.pop
                hash[context][key]['usage'] = parts.pop
                hash[context][key]['available'] = parts.pop
                hash[context][key]['used'] = parts.pop
                hash[context][key]['size'] = parts.pop
                hash[context][key]['type'] = parts.pop       
              end
            when 'mounts'
              parts = line.strip.split(' ')
              key = parts.shift
              hash[context][key] ||= {}
              hash[context][key]['mountpoint'] = parts.shift
              hash[context][key]['format'] = parts.shift
              hash[context][key]['params'] = parts.shift
              hash[context][key]['dump'] = parts.shift
              hash[context][key]['pass'] = parts.shift
            when 'cpu'
              parts = line.strip.split(' ')
              hash[context] ||= {}
              hash[context]['last_minute_load'] = parts.shift
              hash[context]['last_5_minutes_load'] = parts.shift
              hash[context]['last_15_minutes_load'] = parts.shift
              hash[context]['x1'] = parts.shift
              hash[context]['x2'] = parts.shift
              hash[context]['cpus'] = parts.shift
            when 'md'  
              parts = line.strip.split(':')
              key = parts.shift.try(:strip)
              value = (parts * ':')
              parts = value.split(' ')
            
              if key.blank?
              elsif key == 'Personalities'
                hash[context][key.underscore] = parts#.map(&:strip)
              elsif key == 'unused devices'
                hash[context]['unused_devices'] = value.strip
              else
                if value.blank? and dev
                  if key =~ /^[0-9]+ blocks/
                    parts = key.split(' ')
                    hash[context]['devs'][dev]['blocks'] = parts.shift  
                    parts.shift # the word 'blocks'
                    hash[context]['devs'][dev]['disks_status'] = parts.pop
                    hash[context]['devs'][dev][parts.shift] = parts.shift
                  elsif key =~ /recovery =/
                    hash[context]['devs'][dev]['recovery'] = {}
                    hash[context]['devs'][dev]['recovery']['percentage'] = key.scan(/recovery = (.*)%/).first.try :first
                    hash[context]['devs'][dev]['recovery']['done'], hash[context][dev][:recovery][:total] = key..scan(/\((.*)\/(.*)\)/).first
                    hash[context]['devs'][dev]['recovery']['finish'].scan(/finish=([^ ]*)/).first.try :first
                    hash[context]['devs'][dev]['recovery']['speed'].scan(/speed=([^ ]*)/).first.try :first                    
                  else
                    hash[context]['devs'][dev][:line2] = key
                  end
                else
                  dev = key
                  hash[context]['devs'] ||= {}
                  hash[context]['devs'][dev] ||= {}
                  hash[context]['devs'][dev]['status'] = parts.shift
                  hash[context]['devs'][dev]['raid_level'] = parts.shift
                  disks = {}
                  parts.each do |part|
                    disk, i = part.scan(/(.*)\[([0-9+])\]/).first
                    disks[i] = disk
                  end
                  hash[context]['devs'][dev]['disks'] = disks.sort.map{|e| e.last}
                end
              end
            when 'smart'
              if line[0] == "["
                dev = line.strip.gsub(/\[\/dev\/(.*)\]/, '\1')
                hash[context][dev] ||= {}
              else
                k,v = line.split(':').map(&:strip)
                k = k.underscore.gsub(/\W/, '_')
                
                hash[context][dev][k] = v ? v.split(' ').first : '-'
              end
            when 'sensors'  
              if sensors_adapter.nil?
                sensors_adapter = line.strip
                next
              end
  
              if line.strip.empty?
                sensors_adapter = nil
                next
              end
  
              if sensors_adapter
                k,v = line.strip.split(':')
  
                if v.nil?
                  if sensor
                    hash[context][sensor] = sensor_result
                  end
                  sensor = k.underscore.gsub(/\W/, '_')
                  sensor_result = {'adapter' => sensors_adapter, 'label' => sensor}
                else
                  if sensor_result
                    null, type, null, label = k.strip.match(/([a-z]*)([0-9]*_)(.*)/).to_a
                    sensor_result['type'] = type unless type.nil?
                    sensor_result[label] = v.to_f if label
                  end
                end
              end
            when 'lxd'
              lxd_yaml << line
            else
              hash[context]['data'] ||= ''
              hash[context]['data'] << line
            end
          else
            puts line
          end
          
          #hash[context][:_debug] ||= ''
          #hash[context][:_debug] << line
        end
      end
      
      hash
    end
  end
end