require 'time' # for Time.strptime
require 'shellwords'

module CloudModel
  module Mixins
    # Provides backup rotation helpers for models that store timestamped backup
    # directories under {#backup_directory}.
    #
    # Including classes must implement `backup_directory` returning the absolute
    # path of the backup root. Backup snapshots are named with 14-digit timestamps
    # (`YYYYMMDDHHmmSS`). A `latest` symlink is maintained pointing to the most
    # recent snapshot.
    #
    # The retention policy keeps:
    # - The 3 most recent snapshots unconditionally
    # - All snapshots from the last 3 days
    # - One snapshot per day for days 3–6
    # - One snapshot per week for weeks 1–6
    # - One snapshot per month for months 1–6
    module BackupTools
      # Returns all existing backup timestamps, newest first.
      # @return [Array<String>] e.g. `["20240315120000", "20240314120000"]`
      def list_backups
        begin
          Dir.entries(backup_directory).select{|x| x.match /\A[0-9]{14}\z/}.sort{|x,y| y<=>x}
        rescue Errno::ENOENT # No backup dir exists or is empty
          return []
        end
      end

      # Records a successful backup in the database, so freshness monitoring
      # works from ANY machine — the filesystem symlink is only visible on the
      # host that stores the backups, and a second monitoring runner without
      # local backups would otherwise flag "no backup" forever.
      def record_successful_backup
        return unless respond_to? :last_successful_backup_at
        update_attribute :last_successful_backup_at, Time.now
      rescue => e
        # The stamp only serves remote monitoring runners — a bookkeeping
        # problem must never fail a backup that actually succeeded.
        Rails.logger.warn "Could not record backup timestamp: #{e.message}"
      end

      # Time of the most recent *successful* backup, or nil if none exists.
      #
      # Prefers the database timestamp (written by {#record_successful_backup},
      # visible to every monitoring runner); falls back to the local `latest`
      # symlink for backups made before that field existed.
      #
      # Symlink semantics: resolved via `latest` rather than the newest entry in
      # {#list_backups}: the symlink is only re-pointed once a `backup` run has
      # fully succeeded, whereas a run that crashes mid-dump (OOM, timeout,
      # kill) can leave a newer but incomplete timestamp directory behind. The
      # symlink is therefore the only reliable marker of success.
      #
      # A dangling `latest` (the target snapshot was removed, e.g. by retention
      # while no fresh backup replaced it) counts as a failure and returns nil
      # so monitoring flags it — `File.exist?` follows the link, so it is false
      # when the target is gone.
      # @return [Time, nil]
      def last_backup_at
        fs = filesystem_last_backup_at
        return fs if fs

        if File.directory? backup_directory
          # This machine stores (or stored) backups for the subject — the
          # filesystem is authoritative here. No valid `latest` means the
          # backups are gone or never completed: alert, regardless of a
          # possibly fresher DB stamp (catches deleted backups).
          nil
        else
          # Machine without local backups (e.g. a second monitoring runner):
          # trust the DB stamp written by record_successful_backup.
          respond_to?(:last_successful_backup_at) ? last_successful_backup_at : nil
        end
      end

      # The `latest`-symlink based local check (see above for the
      # symlink-over-listing rationale).
      # @return [Time, nil]
      def filesystem_last_backup_at
        link = "#{backup_directory}/latest"
        return nil unless File.symlink? link # no successful backup yet
        return nil unless File.exist? link   # dangling latest => fail

        timestamp = File.basename File.readlink(link)
        return nil unless timestamp =~ /\A[0-9]{14}\z/

        Time.strptime(timestamp, "%Y%m%d%H%M%S")
      rescue ArgumentError, SystemCallError # Unparsable timestamp / unreadable link
        nil
      end
    
      # All backups with display metadata (for the admin UI), newest first.
      # Sizes come from a single `du` call over all backup dirs.
      # @return [Array<Hash>] {timestamp:, time:, size_bytes:, latest:}
      def backups_with_info
        latest = begin
          File.basename File.readlink("#{backup_directory}/latest")
        rescue SystemCallError
          nil
        end

        sizes = backup_sizes
        list_backups.map do |timestamp|
          {
            timestamp: timestamp,
            time: (Time.strptime(timestamp, "%Y%m%d%H%M%S") rescue nil),
            size_bytes: sizes[timestamp],
            latest: timestamp == latest
          }
        end
      end

      # On-disk size of every backup dir in one `du` call.
      # @return [Hash{String => Integer}] timestamp => bytes
      def backup_sizes
        backups = list_backups
        return {} if backups.empty?

        paths = backups.map { |timestamp| "#{backup_directory}/#{timestamp}".shellescape }
        `du -sk #{paths.join(' ')} 2>/dev/null`.lines.to_h do |line|
          size, path = line.split("\t", 2)
          [File.basename(path.to_s.strip), size.to_i * 1024]
        end
      end

      # Returns backup timestamps that fall outside the retention policy and can
      # be safely deleted.
      # @return [Array<String>] timestamps eligible for deletion
      def list_disposable_backups
        CloudModel::Mixins::BackupTools.disposable_timestamps list_backups
      end

      # The retention policy itself, applicable to any list of 14-digit backup
      # timestamps (dump directories, ZFS snapshot names, …): returns the
      # timestamps that fall outside the policy documented above.
      # @param backups [Array<String>] 14-digit timestamps, any order
      # @return [Array<String>] timestamps eligible for deletion
      def self.disposable_timestamps backups
        backups = backups.sort{|a,b| b<=>a}

        #puts "\n ALL #{backups * ', '}"

        now = Time.now
      
        keep_backups = backups[0..2] # always keep last 3 updates
      
        # keep all backups in the last 3 days
        keep_backups += backups.select{|x| x >= (now - 3.days).strftime("%Y%m%d%H%M%S")}
      
        # limit backups to the last 6 month (exept less than 3)
        last_backups = backups.select{|x| x >= (now - 6.month).strftime("%Y%m%d%H%M%S")}
      
        # keep one backup each for the last 6 days
        (3..6).each do |n|
          keep = last_backups.select{|x| x <= (now - (n+1).days).strftime("%Y%m%d%H%M%S")}.first
          #puts "Keep for Day    #{n} (#{(now - (n+1).days).strftime("%Y%m%d%H%M%S")}): #{keep}"
          keep_backups << keep
        end
      
        # keep one backup each for the last 6 weeks
        (1..6).each do |n|
          keep = last_backups.select{|x| x <= (now - (n+1).weeks).strftime("%Y%m%d%H%M%S")}.first
          #puts "Keep for Week   #{n} (#{(now - (n+1).weeks).strftime("%Y%m%d%H%M%S")}): #{keep}"
          keep_backups << keep
        end
        # keep one backup each for the last 6 month
        (1..6).each do |n|
          keep = last_backups.select{|x| x <= (now - (n+1).month).strftime("%Y%m%d%H%M%S")}.first
          #puts "Keep for Month #{"%2d" % n} (#{(now - (n+1).month).strftime("%Y%m%d%H%M%S")}): #{keep}"
          keep_backups << keep
        end
        disposible_backups = backups - keep_backups
      
        Rails.logger.debug "Keep backups: #{keep_backups.uniq * ', '}"
        Rails.logger.debug "Dispose backups: #{disposible_backups * ', '}"
        #puts "KEEP #{keep_backups.uniq * ', '}"
        #puts "DISP #{disposible_backups * ', '}"
      
        disposible_backups
      end
    
      # Deletes all disposable backup directories as determined by {#list_disposable_backups}.
      # @return [true]
      def cleanup_backups
        list_disposable_backups.each do |backup|
          FileUtils.rm_rf "#{backup_directory}/#{backup}"
        end
      
        true
      end
    end
  end
end