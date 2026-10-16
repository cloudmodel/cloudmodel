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

    # Rootfs cloned from the guest template's ZFS build volume (current deploy
    # path): web releases are ZFS clones attached as disk devices.
    ROOTFS_TEMPLATE_VOLUME = 'template_volume'.freeze
    # Rootfs created from an LXD image (the retired tarball path): web releases
    # are plain directories inside the container, which the current web image
    # rollout cannot update — the guest needs one full redeploy first.
    ROOTFS_IMAGE = 'image'.freeze

    # Where the container's rootfs came from (see the constants above). nil for
    # containers that predate the field; {#detect_rootfs_origin!} resolves it
    # from the dataset's ZFS origin.
    field :rootfs_origin, type: String

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
      init_empty_container
      begin
        attach_template_volume
      rescue Exception => e
        # Don't leave an orphaned LXD entry behind when the swap failed
        lxc "delete #{name}"
        raise e
      end
    end

    # Registers the container with LXD without any rootfs content of its own
    # — attach_template_volume swaps the dataset in right after. -s adds a
    # root disk from the storage pool to the instance itself; relying on the
    # host's default profile fails with "No root device could be found" on
    # hosts where lxd init didn't add one.
    #
    # `lxc init --empty` is LXD 4.x+. On an older LXD (3.0 on the Ubuntu
    # 18.04 hosts) the same thing is done from a once-imported empty image:
    # the container then starts life as a clone of that (empty) image
    # dataset, which the swap destroys anyway.
    def init_empty_container
      success, out = lxc "init #{name} --empty -s default"
      return if success
      raise "Failed to init LXD container:\n\n#{out}" unless out.to_s =~ /unknown flag: --empty/

      lxc! "init #{host.ensure_lxd_empty_image!} #{name} -s default", "Failed to init LXD container from the empty image"
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
      record_rootfs_origin ROOTFS_TEMPLATE_VOLUME
    end

    def template_volume_clone?
      rootfs_origin == ROOTFS_TEMPLATE_VOLUME
    end

    # True for containers still on the retired image/tarball layout.
    def legacy_layout?
      rootfs_origin == ROOTFS_IMAGE
    end

    def rootfs_origin_known?
      rootfs_origin.present?
    end

    # Resolves the rootfs origin of an existing container from its dataset's
    # ZFS `origin` property: a clone of a template build volume means the
    # current layout, anything else (an LXD image clone, or no origin at all)
    # the retired one. Persists the result; returns it, or nil if the host
    # could not be asked.
    def detect_rootfs_origin!
      success, origin = host.exec "zfs get -H -o value origin #{root_dataset}"
      return nil unless success

      origin = origin.to_s.strip
      return nil if origin.empty?

      detected = if origin.start_with? "#{CloudModel.config.build_dataset}/"
        ROOTFS_TEMPLATE_VOLUME
      else
        ROOTFS_IMAGE
      end
      record_rootfs_origin detected
      detected
    end

    # Host-side uid the container's id 0 maps to (its unprivileged idmap
    # base). Needed for files the container sees through raw disk devices
    # (web release clones): those are not shifted by LXD, so their host-side
    # owners must already be the mapped ids. Read from LXD once and kept.
    DEFAULT_IDMAP_BASE = 100_000

    field :idmap_base, type: Integer

    def idmap_base
      self[:idmap_base] || detect_idmap_base! || DEFAULT_IDMAP_BASE
    end

    # @return [Integer, nil] base read from the container's idmap, nil if
    #   LXD gave no usable answer
    def detect_idmap_base!
      %w(volatile.idmap.current volatile.idmap.next volatile.idmap.base).each do |key|
        success, raw = lxc "config get #{name} #{key}"
        next unless success and raw.to_s.strip.present?

        base = if key == 'volatile.idmap.base'
          raw.to_s.strip.to_i
        else
          entries = JSON.parse(raw) rescue next
          entry = entries.find { |e| e['Isuid'] and e['Nsid'].to_i == 0 }
          entry && entry['Hostid'].to_i
        end
        next unless base and base > 0

        self[:idmap_base] = base
        set idmap_base: base if persisted?
        return base
      end
      nil
    end

    # @param container_uid [Integer] a uid as seen inside the container
    # @return [Integer] that uid as seen on the host
    def host_uid container_uid
      idmap_base + container_uid.to_i
    end

    def record_rootfs_origin origin
      self.rootfs_origin = origin
      # Atomic $set: this also runs from the after_create callback, where a
      # nested save would re-enter the callback chain.
      set rootfs_origin: origin if persisted?
      origin
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
      return [true, mountpoint] if mounted?

      success, out = host.exec "zfs mount #{root_dataset}"
      unless success
        # LXD switches its datasets to mountpoint=legacy whenever it mounts
        # them itself (e.g. to rewrite backup.yaml after a device was added),
        # and zfs then refuses to mount them ("use mount(8)"). Mount it the
        # legacy way at the path LXD uses, so the offline deploy steps keep
        # writing into the volume.
        raise "Failed to mount containers fs:\n\n#{out}" unless out =~ /legacy mountpoint/
        host.exec! "mkdir -p #{mountpoint.shellescape} && mount -t zfs #{root_dataset.shellescape} #{mountpoint.shellescape}",
          "Failed to mount containers fs (legacy mountpoint)"
      end

      [true, mountpoint]
    end

    def unmount
      success, out = host.exec "zfs unmount #{root_dataset}"
      return [success, out] if success

      # LXD creates its datasets with mountpoint=legacy, and zfs refuses to
      # unmount those ("use umount(8)"). Find where it is mounted and umount
      # it there — the failure path of a deploy must not leave the half-built
      # container's rootfs mounted.
      target = host.exec("findmnt -n -o TARGET -S #{root_dataset.shellescape}")[1].to_s.strip
      return [success, out] if target.empty?

      host.exec "umount #{target.shellescape}"
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
