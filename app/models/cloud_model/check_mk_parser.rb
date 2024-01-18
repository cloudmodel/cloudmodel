module CloudModel
  class CheckMkParser
    def self.parse_cgroup_cpu result, cpus
      calc_usage = proc do |base, data|
        if base.blank? or data.blank?
          [nil,nil]
        else
          age = base[0].to_i - data[0].to_i

          usage = 0
          usage_by_cpus = []

          data[1].each.with_index do |d,i|
            used = base[1][i].to_i - d.to_i
            usage_by_cpus << (100.0 * used / age).round(4)
          end

          usage = (usage_by_cpus.inject(0, :+) / cpus.to_i).round(2)

          [usage, usage_by_cpus]
        end
      end

      if data = result['data']
        lines = data.lines.to_a

        base = lines.shift
        base_ts, *base_usage = base.split(' ') if base

        raw = {}
        lines.reverse.each do |line|
          ts,*usage = line.split(' ')

          age = 1.0*(base_ts.to_i - ts.to_i)/1000000000

          if age <= 15 * 60
            raw[15] = [ts, usage]
          end
          if age <= 5 * 60
            raw[5] = [ts, usage]
          end
          if age <= 1 * 60
            raw[1] = [ts, usage]
          end
        end

        result['cpus'] = cpus #raw[1][1].size

        result['last_minute_percentage'], result['last_minute_percentage_by_cpus'] = calc_usage.call [base_ts, base_usage], raw[1]
        result['last_5_minutes_percentage'], result['last_5_minutes_percentage_by_cpus'] = calc_usage.call [base_ts, base_usage], raw[5]
        result['last_15_minutes_percentage'], result['last_15_minutes_percentage_by_cpus'] = calc_usage.call [base_ts, base_usage], raw[15]
        result
      end
    end

    def self.parse result
      hash = {}
      context = ''
      dev = nil
      sensors_adapter = nil
      sensor = nil
      sensor_result = nil
      lxd_yaml = ''
      _df_block = true
      _in_systemd_units_block = "unknown"
      _systemd_unit = ''

      result.lines.each do |line|
        if line[0..2] == '<<<'
          if context == 'sensors'
            if sensor
              hash['sensors'][sensor] = sensor_result
            end
          end

          if context == 'lxd'
            hash['lxd'] = YAML.load(lxd_yaml, permitted_classes: [Symbol, Time]) unless lxd_yaml.blank?

            hash['lxd'].each do |container|
              if container['container']
                c = container.delete('container')
                container.merge! c
              end

              %w(config expanded_config).each do |field|
                config = {}
                container[field].each do |k,v|
                  keys = k.split('.')
                  prev = config
                  keys.each_with_index do |sk,i|
                    prev[sk] ||= {}
                    if i + 1 == keys.size
                      prev[sk] = v
                    else
                      prev = prev[sk]
                    end
                  end
                end

                if config['volatile'] and config['volatile']['id_map']
                  config['volatile']['id_map']['next'] = JSON.parse config['volatile']['id_map']['next'].gsub('\"', '"')
                  config['volatile']['id_map']['last_state'] = JSON.parse config['volatile']['id_map']['last_state'].gsub('\"', '"')
                end
                container[field] = config
              end
            end
          end

          context = line.gsub(/^<<</, '').gsub(/>>>\n$/, '')
          unless context =~ /:/
            hash[context] ||= {}
          end
        else # some data
          if hash[context]
            case context
            when 'check_mk', 'mem'
              parts = line.strip.split(':')
              key = parts.shift.underscore
              hash[context][key] = (parts * ':').strip
            when 'df', 'df_v2'
              parts = line.strip.split(' ')
              key = parts.shift
              if key == "tmpfs"
                key = "tmpfs#{parts[-1]}"
              end

              if ["[df_inodes_start]", "[df_lsblk_start]"].include? key
                _df_block = false
              elsif ["[df_inodes_end]", "[df_lsblk_end]"].include? key
                _df_block = true

              elsif _df_block
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
              # only parse line 1 on current check_mk_agent
              unless parts[1].blank?
                hash[context]['last_minute_load'] = parts.shift
                hash[context]['last_5_minutes_load'] = parts.shift
                hash[context]['last_15_minutes_load'] = parts.shift
                hash[context]['x1'] = parts.shift
                hash[context]['x2'] = parts.shift
                hash[context]['cpus'] = parts.shift
              end
            when 'lxc_container_cpu'
              lines = line.strip.split("/n")
              hash[context] ||= {}

              lines.each do |line|
                parts = line.split(' ')
                hash[context][parts.shift] ||= parts * ' '
              end
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
                  if hash[context]['devs'][dev]['raid_level'] =~ /\A\(/
                    hash[context]['devs'][dev]['status_note'] = hash[context]['devs'][dev]['raid_level'].delete('()')
                    hash[context]['devs'][dev]['raid_level'] = parts.shift
                  end

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
            when 'zpools'
              zp = line.split("\t").map(&:strip)

              hash[context][zp[0]] = {
                size: zp[1],
                alloc: zp[2],
                free: zp[3],
                expandsz: zp[4],
                frag_percentage: zp[5],
                cap_percentage: zp[6],
                dedup: zp[7],
                health: zp[8],
                altroot: zp[9]
              }
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
            when 'systemd'
              parts = line.strip.split(' ')
              hash[context] ||= {}
              unit = parts.shift
              hash[context][unit] ||= {}
              hash[context][unit]['load'] = parts.shift
              hash[context][unit]['active'] = parts.shift
              hash[context][unit]['sub'] = parts.shift
              hash[context][unit]['description'] = parts * ' '
            when 'lxd'
              lxd_yaml << line
            when "systemd_units"
              #_in_systemd_units_block ||= "unknown"
              if line.strip =~ /\A\[.*\]\z/
                _in_systemd_units_block = line.strip.delete('[]')
                #puts "Switched systemd units block to #{_in_systemd_units_block}"
              else
                case _in_systemd_units_block
                when 'list-unit-files'
                  _systemd_unit, state, preset = line.split(' ')

                  hash[context][_systemd_unit] ||= {}
                  hash[context][_systemd_unit]['state'] = state
                  hash[context][_systemd_unit]['preset'] = preset
                when 'all'
                  _systemd_unit, loaded, active, sub, *description = line.split(' ')

                  hash[context][_systemd_unit] ||= {}
                  hash[context][_systemd_unit]['load'] = loaded
                  hash[context][_systemd_unit]['active'] = active
                  hash[context][_systemd_unit]['sub'] = sub
                  hash[context][_systemd_unit]['description'] = description * ' '
                when 'status'
                  unless _systemd_unit
                    _systemd_unit = line.split(' ')[1]
                    #puts "Switched systemd unit to #{_systemd_unit}"
                  end

                  if line.blank?
                    _systemd_unit = nil
                  else
                    hash[context][_systemd_unit] ||= {}
                    hash[context][_systemd_unit]['status'] ||= ''
                    hash[context][_systemd_unit]['status'] << line.force_encoding('ASCII-8BIT').encode("UTF-8", invalid: :replace, undef: :replace)
                    #puts "#{_systemd_unit}: #{hash[context][_systemd_unit]['status']}"
                  end

                  #puts line
                else
                  puts line
                end
              end
            else
              unless line.blank?
                hash[context]['data'] ||= ''
                hash[context]['data'] << line
              end
            end
          else
            real_context, sep = context.split(':')
            if sep
              hash[real_context] ||= {}
              hash[real_context]["data_#{sep}"] ||= ''
              hash[real_context]["data_#{sep}"] << line
            else
              puts "#{context}: #{line}"
            end
          end

          #hash[context][:_debug] ||= ''
          #hash[context][:_debug] << line
        end
      end

      if hash['cgroup_cpu']
        if hash['cpu']
          # Ubuntu 18.04 guest/host
          parse_cgroup_cpu hash['cgroup_cpu'], hash['cpu']['cpus']
        elsif hash['lxc_container_cpu']
          # Ubuntu 22.04 guest
          res = parse_cgroup_cpu hash['cgroup_cpu'], hash['lxc_container_cpu']['num_cpus']
          hash['cpu'] ||= res
        end
      end

      if hash['df_v2']
        hash['df'] = hash.delete 'df_v2'
      end

      hash
    end
  end
end