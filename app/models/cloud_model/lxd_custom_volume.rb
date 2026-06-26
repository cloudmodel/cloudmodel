module CloudModel
  # A persistent LXD ZFS storage volume embedded in a {Guest}.
  #
  # Unlike the root filesystem (which is replaced on every redeploy), custom
  # volumes survive redeployments and are re-attached to the new container.
  # They are backed by ZFS datasets under `guests/custom/<name>` on the host.
  #
  # The volume name is auto-generated from the guest name and mount point on
  # validation. Backups are performed via rsync to the configured backup hosts
  # when `has_backups` is true.
  class LxdCustomVolume
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::AcceptSizeStrings
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    embedded_in :guest, class_name: "CloudModel::Guest"

    field :name, type: String
    field :pool, type: String, default: 'default'
    field :disk_space, type: Integer, default: 10737418240

    field :mount_point, type: String
    field :writeable, type: Mongoid::Boolean, default: true
    field :has_backups, type: Mongoid::Boolean, default: false

    validates :name, presence: true
    validates :name, uniqueness: { scope: :host }
    validates :name, format: {with: /\A[A-Za-z0-9][A-Za-z0-9\-_]*\z/}

    validates :mount_point, presence: true
    validates :mount_point, uniqueness: { scope: :guest }
    validates :mount_point, format: {with: /\A[A-Za-z0-9][A-Za-z0-9\-_\/]*\z/}

    accept_size_strings_for :disk_space

    before_validation :set_volume_name
    after_create :create_volume!, unless: :skip_volume_creation
    before_destroy :before_destroy, unless: :skip_volume_creation

    attr_accessor :skip_volume_creation

    def host
      guest.host
    end

    def before_destroy
      if used?
        puts "Can't destroy attached volume; unattach it first"
        return false
      end

      success, output = destroy_volume
      unless success
        puts "Failed to destroy LXD volume"
      end
      success
    end

    def volume_exists?
      success, output = lxc "storage volume show #{pool.shellescape} #{name.shellescape}"
      not(success == false and ["Error: not found", "Error: Storage pool volume not found"].include? output.strip)
    end

    def create_volume
      lxc "storage volume create #{pool.shellescape} #{name.shellescape}"
    end

    def create_volume!
      unless guest.deploy_state == :not_started
        lxc! "storage volume create #{pool.shellescape} #{name.shellescape}", "Failed to init LXD volume"
      end
    end

    def destroy_volume
      lxc "storage volume delete #{pool.shellescape} #{name.shellescape}"
    end

    def to_param
      name
    end

    def item_issue_chain
      [host, guest, self]
    end

    # Get infos about the volume
    def lxc_show
      success, result = lxc "storage volume show #{pool.shellescape} #{name.shellescape}"
      begin
        YAML.load(result, permitted_classes: [Symbol, Time]).deep_transform_keys { |key| key.to_s.underscore }
      rescue
        {'error' => "No valid YAML: #{result}"}
      end
    end

    def used?
      result = lxc_show
      result && result['used_by'] && result['used_by'].size > 0
    end

    def usage_bytes
      begin
        zfs_pool = pool == 'default' ? 'guests' : pool
        if check_result = guest.monitoring_last_check_result and sys_info = check_result['system'] and df = sys_info['df'] and info = df["#{zfs_pool}/custom/#{name}".to_sym] or info = df["#{zfs_pool}/custom/default_#{name}".to_sym]
          info['used'].to_i*1024
        end
      rescue
      end
    end

    def usage_percentage
      if usage_bytes and disk_space
        (100.0 * usage_bytes / disk_space)
      else
        nil
      end
    end

    def host_path
      "/var/lib/lxd/storage-pools/#{pool.shellescape}/custom/#{name}/"
    end

    # Backup
    #
    # Physical, incremental, pull-based ZFS backup orchestrated from the admin
    # instance: an atomic `zfs snapshot` is taken on the guest's host and
    # `zfs send` (incremental against the previous snapshot) is piped over SSH
    # into a `zfs receive` on the pool of the host THIS instance runs on
    # ({CloudModel::Host.local}). The target dataset is derived from
    # {CloudModel.config.backup_directory} (no extra config). The atomic
    # snapshot is crash-consistent, so a running service (e.g. MongoDB with
    # journaling on the same dataset) is safe to snapshot — unlike the previous
    # rsync of live files. ZFS manages the incremental chain and retention
    # natively (old snapshots pruned with `zfs destroy`), so there are no stream
    # files and no need for periodic full backups.

    # Prefix for the ZFS snapshots this backup creates.
    ZFS_BACKUP_SNAPSHOT_PREFIX = 'coreon-bkp-'

    # Number of received snapshots to keep on the backup host.
    ZFS_BACKUP_KEEP = 30

    def backup_directory
      "#{CloudModel.config.backup_directory}/#{host.id}/#{guest.id}/volumes/#{id}"
    end

    # Host-side ZFS dataset backing this volume. LXD prefixes the project name
    # ("default_") on custom-volume datasets; older volumes may not have it, so
    # resolve against the actual dataset list on the host.
    # @return [String, nil]
    def zfs_dataset
      return @zfs_dataset if defined? @zfs_dataset
      zfs_pool = pool == 'default' ? 'guests' : pool
      candidates = ["#{zfs_pool}/custom/default_#{name}", "#{zfs_pool}/custom/#{name}"]
      success, out = host.exec "zfs list -H -o name -t filesystem"
      @zfs_dataset = success ? candidates.find { |c| out.split("\n").include?(c) } : nil
    end

    # Backup snapshots present on the source dataset, newest first.
    # @return [Array<String>] full snapshot names (`dataset@coreon-bkp-<ts>`)
    def zfs_backup_snapshots
      return [] unless dataset = zfs_dataset
      success, out = host.exec "zfs list -H -o name -t snapshot -r #{dataset.shellescape}"
      return [] unless success
      out.split("\n").select { |s| s.start_with? "#{dataset}@#{ZFS_BACKUP_SNAPSHOT_PREFIX}" }.sort.reverse
    end

    # Time of the most recent successful backup (the newest snapshot kept on the
    # source as the next incremental base). Overrides the symlink-based
    # BackupTools#last_backup_at, which does not apply to ZFS backups.
    # @return [Time, nil]
    def last_backup_at
      snapshot = zfs_backup_snapshots.first
      return nil unless snapshot
      ts = snapshot.split("@#{ZFS_BACKUP_SNAPSHOT_PREFIX}").last
      return nil unless ts =~ /\A[0-9]{14}\z/
      Time.strptime(ts, "%Y%m%d%H%M%S")
    rescue ArgumentError
      nil
    end

    def backup
      return false unless has_backups

      source = zfs_dataset
      unless source
        Rails.logger.error "ZFS backup: no source dataset found for volume #{name}"
        return false
      end

      target = backup_target_dataset
      unless target
        Rails.logger.error "ZFS backup: cannot resolve backup target dataset for volume #{name}"
        return false
      end

      timestamp = Time.now.strftime "%Y%m%d%H%M%S"
      base = zfs_backup_snapshots.first # newest existing -> incremental base
      snapshot = "#{source}@#{ZFS_BACKUP_SNAPSHOT_PREFIX}#{timestamp}"

      # 1. atomic, crash-consistent snapshot on the source host (quiescing the
      #    owning service first, if it asks to — e.g. MongoDB fsyncLock)
      unless take_consistent_snapshot snapshot
        Rails.logger.error "ZFS backup: failed to snapshot #{snapshot}"
        return false
      end

      # 2. pull the (incremental) stream and receive it into the backup host
      if send_to_backup_host snapshot, base, target
        prune_source_snapshots keep: snapshot # keep newest as next -i base
        prune_target_snapshots target         # native, chain-safe retention
        true
      else
        host.exec "zfs destroy #{snapshot.shellescape}" # failed transfer -> drop snapshot
        false
      end
    end

    # Restore a snapshot back onto the source dataset by sending it from the
    # backup host. The volume must be detached / the container stopped, as
    # `zfs receive -F` rolls the source dataset back.
    # @param timestamp [String] 'latest' or a 14-digit backup timestamp
    def restore timestamp = 'latest'
      source = zfs_dataset
      target = backup_target_dataset
      return false unless source and target

      snapshot = if timestamp == 'latest'
        success, out = backup_host.exec "zfs list -H -o name -t snapshot -r #{target.shellescape}"
        return false unless success
        out.split("\n").select { |s| s.include? "@#{ZFS_BACKUP_SNAPSHOT_PREFIX}" }.sort.last
      else
        "#{target}@#{ZFS_BACKUP_SNAPSHOT_PREFIX}#{timestamp}"
      end
      return false unless snapshot

      ssh = ssh_command
      command = "#{ssh} root@#{backup_host.private_address} \"zfs send #{snapshot.shellescape}\" | " +
                "#{ssh} root@#{host.private_address} \"zfs receive -F #{source.shellescape}\""
      Rails.logger.debug command
      Rails.logger.debug `#{command}`
      $?.success?
    end

    private

    # Take the source snapshot, quiescing the service whose data lives on this
    # volume first (if it asks to, e.g. MongoDB fsyncLock). The ZFS snapshot is
    # already crash-consistent; this is extra safety for a checkpoint-clean image.
    # @return [Boolean] whether the snapshot succeeded
    def take_consistent_snapshot snapshot
      take = -> { host.exec("zfs snapshot #{snapshot.shellescape}")[0] }
      if service = backed_service
        service.with_backup_consistency { take.call }
      else
        take.call
      end
    end

    # The service on this guest whose data lives on this volume (matched by
    # mount point), if any — used to quiesce it around the snapshot.
    # @return [CloudModel::Services::Base, nil]
    def backed_service
      guest.services.detect { |service| service.backup_data_mount_point == mount_point }
    end

    # The host this cloudmodel instance runs on (the local ZFS receive target).
    def backup_host
      CloudModel::Host.local
    end

    # ZFS dataset that backs the local {CloudModel.config.backup_directory},
    # derived from its mount (inside the container the data volume's mount source
    # is the ZFS dataset name). Returns nil if it is not on ZFS.
    # @return [String, nil]
    def backup_root_dataset
      dir = CloudModel.config.backup_directory
      source = `df --output=source #{dir.shellescape} 2>/dev/null`.lines.last.to_s.strip
      return nil if source.empty? || source.start_with?('/')
      source
    end

    # Per-volume target dataset on the backup host, or nil if unresolvable.
    def backup_target_dataset
      root = backup_root_dataset
      return nil unless root and backup_host
      "#{root}/zfs_backups/#{host.id}/#{guest.id}/#{id}"
    end

    def ssh_command
      "ssh -o StrictHostKeyChecking=no -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa"
    end

    # Pull the (incremental) stream from the source host and `zfs receive` it
    # into the backup host's pool (left unmounted with `-u`). Ensures the parent
    # dataset exists first.
    # @return [Boolean] whether the transfer succeeded
    def send_to_backup_host snapshot, base, target
      ssh = ssh_command
      flags = base ? "-i #{base.shellescape}" : ""
      parent = target.rpartition('/').first
      backup_host.exec "zfs create -p #{parent.shellescape}" unless parent.empty?

      command = "#{ssh} root@#{host.private_address} \"zfs send #{flags} #{snapshot.shellescape}\" | " +
                "#{ssh} root@#{backup_host.private_address} \"zfs receive -F -u #{target.shellescape}\""
      Rails.logger.debug command
      Rails.logger.debug `#{command}`
      $?.success?
    end

    # Destroy all backup snapshots on the source except `keep` (the new base).
    def prune_source_snapshots keep:
      zfs_backup_snapshots.each do |snapshot|
        next if snapshot == keep
        host.exec "zfs destroy #{snapshot.shellescape}"
      end
    end

    # Keep the most recent {ZFS_BACKUP_KEEP} snapshots on the backup host,
    # destroy older ones. Chain-safe: the newest (next `-i` base) is retained.
    def prune_target_snapshots target
      success, out = backup_host.exec "zfs list -H -o name -t snapshot -r #{target.shellescape}"
      return unless success
      snapshots = out.split("\n").select { |s| s.include? "@#{ZFS_BACKUP_SNAPSHOT_PREFIX}" }.sort # oldest first
      (snapshots[0...-ZFS_BACKUP_KEEP] || []).each do |snapshot|
        backup_host.exec "zfs destroy #{snapshot.shellescape}"
      end
    end

    def set_volume_name
      self.name = "#{guest.name}-#{mount_point.gsub("/", "-")}"
    end

    def lxc command
      host.exec "lxc #{command}"
    end

    def lxc! command, error
      host.exec! "lxc #{command}", error
    end
  end
end
