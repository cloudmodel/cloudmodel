require 'shellwords'

module CloudModel
  # Sweeps the dump backup tree (per-service mongodb/mariadb dumps and
  # replica set dumps) for data nobody else ever deletes:
  #
  # - backups of deleted subjects (guest, service or replica set no longer in
  #   the DB, or guest moved to another host) — the per-subject retention only
  #   runs right after a *successful* backup of that same subject, so orphans
  #   accumulate forever,
  # - backups beyond the retention policy of subjects whose backups are
  #   disabled or currently failing (same reason),
  # - dangling `latest` symlinks and empty directory husks left over from
  #   manual deletions.
  #
  # It never touches backups the retention policy keeps for live subjects and
  # never leaves the configured backup root. ZFS volume backups live in
  # datasets (pruned chain-safe after each send), not in this tree.
  #
  # Runs automatically after every backup run (see the backup rake tasks) and
  # manually via `rake cloudmodel:cleanup:backups` (dry run unless CONFIRM=1).
  class BackupCleanup
    ID_PATTERN = /\A[0-9a-f]{24}\z/

    # Post-backup sweep: deletes for real, but never lets a cleanup problem
    # fail a backup run that just succeeded — the guards (empty DB, missing
    # root) and any unexpected error only report and move on.
    def self.run_after_backup output: $stdout
      output.puts "\nCleaning up obsolete backups:"
      new.cleanup! dry_run: false, output: output
    rescue => e
      output.puts "Backup cleanup skipped: #{e.message}"
      Rails.logger.error "Backup cleanup failed: #{e.message}"
    end

    # @return [String] the configured dump backup root
    def backup_root
      CloudModel.config.backup_directory
    end

    # Guard against running with an empty database (wrong RAILS_ENV would make
    # EVERY backup look orphaned) or a mistyped backup root.
    def sanity_check!
      unless File.directory? backup_root
        raise "Backup root #{backup_root} does not exist"
      end
      if CloudModel::Guest.count == 0 && CloudModel::MongodbReplicationSet.count == 0
        raise "Refusing to clean backups: database has no guests or replica " \
              "sets — forgot RAILS_ENV=production?"
      end
    end

    # Service backup dirs whose host/guest/service is gone from the DB.
    # A guest moved to another host counts as orphaned under the old host id —
    # new backups go to the new path.
    # @return [Array<String>]
    def orphaned_service_dirs
      Dir.glob("#{backup_root}/*/*/services/*").select do |dir|
        host_id, guest_id, _services, service_id = dir.delete_prefix("#{backup_root}/").split('/')
        next false unless [host_id, guest_id, service_id].all? { |id| id.to_s =~ ID_PATTERN }

        guest = CloudModel::Guest.where(id: guest_id, host_id: host_id).first
        guest.nil? || guest.services.where(id: service_id).first.nil?
      end.sort
    end

    # Replica set backup dirs whose set is gone from the DB.
    # @return [Array<String>]
    def orphaned_replset_dirs
      Dir.glob("#{backup_root}/mongodb_replication_sets/*").select do |dir|
        id = File.basename dir
        next false unless id =~ ID_PATTERN
        CloudModel::MongodbReplicationSet.where(id: id).first.nil?
      end.sort
    end

    # Timestamp dirs beyond the retention policy for subjects that still
    # exist. Normally pruned after each successful backup — this catches
    # subjects whose backups are disabled or have been failing for a while.
    # @return [Array<String>]
    def retention_disposable_dirs
      dirs = []

      CloudModel::Guest.all.each do |guest|
        guest.services.each do |service|
          next unless File.directory? service.backup_directory
          service.list_disposable_backups.each do |timestamp|
            dirs << "#{service.backup_directory}/#{timestamp}"
          end
        end
      end

      CloudModel::MongodbReplicationSet.all.each do |set|
        next unless File.directory? set.backup_directory
        set.list_disposable_backups.each do |timestamp|
          dirs << "#{set.backup_directory}/#{timestamp}"
        end
      end

      dirs.sort
    end

    # `latest` symlinks whose target is gone (e.g. manually deleted backups).
    # @return [Array<String>]
    def dangling_latest_links
      Dir.glob("#{backup_root}/**/latest").select do |link|
        File.symlink?(link) && !File.exist?(link)
      end.sort
    end

    # Directories under the root that are currently empty (bottom-up, so
    # nested husks collapse in one pass over repeated calls).
    # @return [Array<String>]
    def empty_dirs
      Dir.glob("#{backup_root}/**/*")
         .select { |path| File.directory?(path) && !File.symlink?(path) }
         .select { |dir| Dir.empty? dir }
         .sort_by(&:length).reverse
    end

    # Total on-disk size of the given paths in bytes (via du).
    # @return [Integer]
    def size_of paths
      paths.reject { |p| p.empty? }.each_slice(100).sum do |slice|
        `du -sk #{slice.map(&:shellescape).join(' ')} 2>/dev/null`.lines.sum { |l| l.to_i } * 1024
      end
    end

    # Remove orphans, over-retention backups, dangling latest links and empty
    # dirs. With dry_run (the default) only prints what would happen.
    def cleanup! dry_run: true, output: $stdout
      sanity_check!
      prefix = dry_run ? '[dry-run] ' : ''
      output.puts 'Dry run — nothing will be deleted.' if dry_run

      orphans = orphaned_service_dirs + orphaned_replset_dirs
      stale = retention_disposable_dirs

      [['orphaned (subject deleted)', orphans],
       ['beyond retention', stale]].each do |label, dirs|
        size = size_of dirs
        output.puts "#{label}: #{dirs.size} dir(s), #{human_size size}"
        dirs.each do |dir|
          output.puts "#{prefix}rm -r #{dir}"
          FileUtils.rm_rf dir unless dry_run
        end
      end

      dangling_latest_links.each do |link|
        output.puts "#{prefix}rm #{link} (dangling latest)"
        File.delete link unless dry_run
      end

      # Collapse empty husks bottom-up; deletions above create new ones, so
      # keep sweeping until nothing is left (single informative pass when
      # dry-running — the husks of not-yet-deleted dirs would be misleading).
      loop do
        empties = empty_dirs
        break if empties.empty?
        empties.each do |dir|
          output.puts "#{prefix}rmdir #{dir}"
          Dir.rmdir dir unless dry_run
        end
        break if dry_run
      end

      true
    end

    private

    def human_size bytes
      ActiveSupport::NumberHelper.number_to_human_size bytes
    end
  end
end
