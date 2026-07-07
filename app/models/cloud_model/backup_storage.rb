require 'shellwords'

module CloudModel
  # Fill level of the backup storage (the device/dataset backing
  # {CloudModel.config.backup_directory}) for the admin UI.
  #
  # Preferred source is ZFS on the backup host — the received volume
  # snapshots live in unmounted child datasets, so only `zfs get` on the
  # root dataset accounts for them. Falls back to a local `df` when the
  # backup directory is not on ZFS.
  module BackupStorage
    # @return [Hash, nil] {size_bytes:, used_bytes:, available_bytes:,
    #   usage_percent:, snapshots_bytes: (ZFS backups subtree, nil w/o ZFS),
    #   dumps_bytes: (dump tree via du)}
    def self.status
      stats = zfs_status || df_status
      return nil unless stats
      stats[:dumps_bytes] = dump_tree_bytes
      stats
    end

    # @return [Hash, nil]
    def self.zfs_status
      root = CloudModel::LxdCustomVolume.backup_root_dataset
      backup_host = CloudModel::Host.local
      return nil unless root && backup_host

      success, out = backup_host.exec "zfs get -Hp -o property,value used,available,quota #{root.shellescape}"
      return nil unless success

      values = out.split("\n").map { |line| line.split("\t").first(2) }.to_h
      used = values['used'].to_i
      available = values['available'].to_i
      size = values['quota'].to_i
      size = used + available if size.zero? # no quota -> bounded by the pool

      snapshots_success, snapshots_out = backup_host.exec "zfs get -Hp -o value used #{"#{root}/zfs_backups".shellescape}"

      {
        size_bytes: size,
        used_bytes: used,
        available_bytes: available,
        usage_percent: (used * 100.0 / [size, 1].max).round(1),
        snapshots_bytes: snapshots_success ? snapshots_out.strip.to_i : 0
      }
    end

    # @return [Hash, nil]
    def self.df_status
      fields = `df -kP #{CloudModel.config.backup_directory.shellescape} 2>/dev/null`.lines.last.to_s.split
      return nil if fields.size < 5

      size = fields[1].to_i * 1024
      used = fields[2].to_i * 1024
      {
        size_bytes: size,
        used_bytes: used,
        available_bytes: fields[3].to_i * 1024,
        usage_percent: (used * 100.0 / [size, 1].max).round(1),
        snapshots_bytes: nil
      }
    end

    # On-disk size of the (locally visible) dump tree.
    # @return [Integer]
    def self.dump_tree_bytes
      `du -sk #{CloudModel.config.backup_directory.shellescape} 2>/dev/null`.split.first.to_i * 1024
    end
  end
end
