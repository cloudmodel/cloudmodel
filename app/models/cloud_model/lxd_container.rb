module CloudModel
  # Represents a single LXD container instance embedded in a {Guest}.
  #
  # A guest may have multiple LxdContainer records representing successive
  # deployments (each deploy creates a new container from the current template).
  # `Guest#current_lxd_container_id` tracks which one is live. Older containers
  # remain in the database and can be started for rollback purposes.
  #
  # All LXD operations are executed via the host's SSH connection using
  # `lxc` CLI commands.
  class LxdContainer
    include Mongoid::Document
    include Mongoid::Timestamps
    prepend CloudModel::Mixins::SmartToString
    include ActiveModel::Validations::Callbacks

    embedded_in :guest, class_name: "CloudModel::Guest"
    belongs_to :guest_template, class_name: "CloudModel::GuestTemplate"

    before_validation :ensure_template_is_set
    after_create :create_container
    before_destroy :before_destroy
    after_destroy :destroy_container

    def before_destroy
      if running?
        puts "Can't destroy running container; stop it first"
        return false
      end

      true
    end

    def host
      guest.host
    end

    def name
      "#{guest.name.shellescape}-#{created_at.try(:utc).try :strftime, "%Y%m%d%H%M%S"}"
    end

    # Command definitions

    def lxc command
      host.exec "echo \"lxc #{command}\" | bash"
    end

    def lxc! command, error
      host.exec! "echo \"lxc #{command}\" | bash", error
    end

    def ensure_template_is_set
      if guest_template.blank?
        if self.persisted?
          #Rails.logger.debug "Set template to #{self.guest.template.name}"
          self.update_attribute :guest_template, self.guest.template
        else
          self.guest_template = self.guest.template
        end
      end
      self
    end

    def root_dataset
      "guests/containers/#{name}"
    end

    def create_container
      Rails.logger.debug "Create lxd container #{name} from ZFS volume #{guest_template.build_dataset}"
      # -s adds a root disk from the storage pool to the instance itself;
      # relying on the host's default profile fails with "No root device
      # could be found" on hosts where lxd init didn't add one.
      lxc! "init #{name} --empty -s default", "Failed to init LXD container"
      begin
        attach_template_volume
      rescue Exception => e
        # Don't leave an orphaned LXD entry behind when the swap failed
        lxc "delete #{name}"
        raise e
      end
    end

    # Swaps the empty container's root dataset for a clone of the guest
    # template's ready snapshot, keeping LXD's bookkeeping (backup.yaml).
    # This is what deploys a template — no image tarballs are involved.
    # The clone still carries host-range uids, so LXD's recorded on-disk
    # idmap is cleared to make it remap the filesystem on first start.
    def attach_template_volume
      mount
      backup_yaml_present, backup_yaml = host.exec "cat #{mountpoint}/backup.yaml"
      unmount
      host.exec! "zfs destroy -r #{root_dataset}", "Failed to remove empty container dataset"
      host.exec! "zfs clone -o mountpoint=#{mountpoint.shellescape} -o canmount=noauto #{guest_template.build_snapshot.shellescape} #{root_dataset}", "Failed to clone template volume"
      mount
      if backup_yaml_present
        host.sftp.file.open("#{mountpoint}/backup.yaml", 'w') { |f| f.write backup_yaml }
      end
      # Template builds don't pre-shift uids (fuidshift isn't available on
      # snap-LXD hosts). An empty last_state.idmap tells LXD the rootfs is
      # unshifted, so it remaps into the container's unprivileged range on
      # first start — preserving suid bits, caps, and ACLs like fuidshift.
      lxc! "config set #{name} volatile.last_state.idmap '[]'", "Failed to reset container idmap state"
    end

    def destroy_container
      lxc "delete #{name}"#, "Failed to destroy LXD container"
    end

    def start
      # Shutdown previous running container of guest
      guest.lxd_containers.each do |c|
        c.stop up_state: :booting, reason: 'Reboot'
      end

      success, result = lxc "start #{name}"
      if success
        guest.update_attributes up_state: :started
      else
        guest.update_attributes up_state: :start_failed, last_downtime_at: Time.now, last_downtime_reason: "LXC start issue: #{result}"
      end
    end

    def stop options={}
      if options[:force] or running?
        guest.update_attributes up_state: options[:up_state] || :stopped, last_downtime_at: Time.now, last_downtime_reason: options[:reason] || "Stopped"
        lxc "stop #{name} -f --timeout=10"
      end
    end

    def mounted?
      success, state = host.exec "zfs get -H -o value mounted #{root_dataset}"
      success and state.to_s.strip == 'yes'
    end

    def mount
      mountpoint # to init mountpoint
      host.exec! "zfs mount #{root_dataset}", "Failed to mount containers fs" unless mounted?
      return [true, mountpoint]
    end

    def unmount
      host.exec "zfs unmount #{root_dataset}"
    end

    def mountpoint
      return @mountpoint if @mountpoint

      res, out = host.exec("zfs list | grep #{root_dataset}")
      if res
        @mountpoint = out.split(' ').last

        if %w(none legacy).include? @mountpoint
          #@mountpoint = "/var/snap/lxd/common/lxd/storage-pools/default/containers/#{name}"
          host.exec("mkdir -p /var/lib/lxd/storage-pools/default/containers")
          @mountpoint = "/var/lib/lxd/storage-pools/default/containers/#{name}"
          host.exec "zfs set mountpoint=#{@mountpoint} canmount=noauto #{root_dataset}"
        end

        #puts @mountpoint

        @mountpoint
      else
        "/tmp/#{name}"
      end
      # if false
      #   # apt-get version of lxd
      #   "/var/lib/lxd/storage-pools/default/containers/#{name}"
      # else
      #   # snap version of lxd
      #   "/var/snap/lxd/common/lxd/storage-pools/default/containers/#{name}"
      # end
    end

    # Get generic infos about the LXD
    def lxd_info
      success, result = lxc "info"
      YAML.load(result, permitted_classes: [Symbol, Time]).deep_transform_keys { |key| key.to_s.underscore }
    end

    # Unroll lxc config values
    def self._unroll_lxc_config_values values
      config = {}

      values.each do |k,v|
        keys = k.split('.')
        prev = config
        prefix = ''
        keys.each_with_index do |sk,i|
          sk = "#{prefix}#{sk}"

          if i + 1 == keys.size
            if prev[sk].nil?
              prev[sk] = v
            else
              prev[sk].keys.each do |subkey|
                prev["#{sk}.#{subkey}"] = prev[sk][subkey]
              end
              prev[sk] = v
            end
          else
            if prev[sk].nil? or prev[sk].is_a? Hash
              prev[sk] ||= {}
              prev = prev[sk]
            else
              prefix = "#{prefix}#{sk}."
            end
          end
        end
      end

      if config['volatile'] and config['volatile']['id_map']
        config['volatile']['id_map']['next'] = JSON.parse config['volatile']['id_map']['next'].gsub('\"', '"')
        config['volatile']['id_map']['last_state'] = JSON.parse config['volatile']['id_map']['last_state'].gsub('\"', '"')
      end

      config
    end

    # Get infos about the container
    def live_lxc_info
      success, result = lxc "list #{name} --format yaml"
      if success
        result = YAML.load(result, permitted_classes: [Symbol, Time]).find{|i| i['name'] == name}

        result ||= {'name' => name, 'status' => 'Unknown', 'empty' => true}

        if result['container']
          container = result.delete('container')
          result = result.merge(container)
        end

        %w(config expanded_config).each do |field|

          if result[field]
            result[field] = CloudModel::LxdContainer._unroll_lxc_config_values result[field]
          end
        end
        result
      else
        {'name' => name, 'status' => 'Unknown'}
      end
    end

    def lxc_info
      if host.monitoring_last_check_result and host.monitoring_last_check_result['system'] and container_info = host.monitoring_last_check_result['system']['lxd']
        container_info.find{|c| c['name'] == name} || {'name' => name, 'status' => 'Unknown'}
      else
        {'name' => name, 'status' => 'Unknown'}
      end
    end


    def running?
      if info = live_lxc_info and state = info['state']
        state['status'] == "Running"
      else
        nil
      end
    end

    def show_config
      res, ret = lxc "config show #{name}"
      if res
        begin
          YAML.load ret
        rescue
          {error: "YAML not parseable", returned: ret}
        end
      else
        nil
      end
    end

    def get_config key
      res, ret = lxc "config get #{name} #{key.to_s.shellescape}"
      if res
        ret = ret.strip
        if ret =~ /^[0-9]+$/
          ret.to_i
        else
          ret
        end
      else
        nil
      end
    end

    def set_config key, value
      lxc "config set #{name} #{key.to_s.shellescape} #{value.to_s.shellescape}"
    end

    def unset_config key
      lxc "config unset #{name} #{key.to_s.shellescape}"
    end

    def config_from_guest
      raw_lxc_config = "lxc.mount.auto = cgroup"

      raw_lxc_config += "\nlxc.apparmor.profile = unconfined"

      set_config 'raw.lxc', raw_lxc_config
      guest.configure_lxd_container self

      lxc "config device set #{name} root size #{guest.root_fs_size}" # todo: fix disk quota

      lxc "network attach lxdbr0 #{name} eth0"
      #lxc "config set #{name} volatile.lxdbr0.hwaddr #{guest.mac_address}"

      # Attach custom storage volumes
      guest.lxd_custom_volumes.each do |volume|
        lxc "storage volume attach #{volume.pool} #{volume.name} #{name} #{volume.mount_point}"
      end
    end
  end
end
