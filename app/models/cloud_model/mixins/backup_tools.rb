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
    # The retention policy (see {.disposable_timestamps}) keeps the newest
    # snapshots, the newest per calendar day, week and month for a configured
    # number of each ({CloudModel::Config#backup_retention}, default: 3 newest,
    # 6 days, 6 weeks, 6 months).
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

      # Delete a single backup version. Re-points the `latest` link to the
      # newest remaining backup (or drops it), and removes the whole backup
      # directory once nothing is left — the next backup recreates it.
      # @param timestamp [String] 14-digit backup timestamp
      # @return [Boolean] whether the backup existed and was deleted
      def delete_backup timestamp
        unless timestamp.to_s =~ /\A[0-9]{14}\z/
          raise ArgumentError, "invalid backup timestamp #{timestamp.inspect}"
        end
        dir = "#{backup_directory}/#{timestamp}"
        return false unless File.directory? dir

        FileUtils.rm_rf dir

        link = "#{backup_directory}/latest"
        begin
          if File.symlink?(link) && File.basename(File.readlink(link)) == timestamp
            File.delete link
            if newest = list_backups.first
              FileUtils.ln_s newest, link # relative — survives release pruning
            end
          end
        rescue SystemCallError
          nil
        end

        if list_backups.empty?
          FileUtils.rm_f link
          begin
            Dir.rmdir backup_directory # only when truly empty — foreign files stay
          rescue SystemCallError
            nil
          end
        end
        true
      end

      # Returns backup timestamps that fall outside the retention policy and can
      # be safely deleted.
      # @return [Array<String>] timestamps eligible for deletion
      def list_disposable_backups
        CloudModel::Mixins::BackupTools.disposable_timestamps list_backups
      end

      # The retention policy itself, applicable to any list of 14-digit backup
      # timestamps (dump directories, ZFS snapshot names, …): returns the
      # timestamps that fall outside it.
      #
      # Grandfather-father-son over calendar buckets, configured by
      # {CloudModel::Config#backup_retention}: the newest backup of each of
      # the last `days` calendar days, of each of the last `weeks` calendar
      # weeks and of each of the last `months` calendar months is kept, plus
      # the `recent` newest backups regardless of age. Each tier picks among
      # the backups that are still there, so a daily backup that ages out of
      # the daily tier is the one the weekly tier keeps — the selection is
      # stable from one run to the next. (The earlier "newest backup older
      # than n days" slots dropped every backup on its fourth day, before any
      # slot could claim it, and kept only three versions in practice.)
      #
      # @param backups [Array<String>] 14-digit timestamps, any order
      # @param retention [Hash] {recent:, days:, weeks:, months:}
      # @param now [Time]
      # @return [Array<String>] timestamps eligible for deletion
      def self.disposable_timestamps backups, retention: CloudModel.config.backup_retention, now: Time.now
        backups = backups.uniq.sort.reverse
        times = backups.each_with_object({}) do |stamp, h|
          h[stamp] = Time.strptime(stamp, '%Y%m%d%H%M%S') rescue nil
        end
        dated = backups.select { |b| times[b] }

        keep = backups.first(retention[:recent].to_i)

        today = now.to_date
        day_buckets = (0...retention[:days].to_i).map { |n| today - n }
        week_buckets = (0...retention[:weeks].to_i).map { |n| (today - 7 * n).beginning_of_week }
        month_buckets = (0...retention[:months].to_i).map { |n| (today << n).beginning_of_month }

        {
          day_buckets => ->(t) { t.to_date },
          week_buckets => ->(t) { t.to_date.beginning_of_week },
          month_buckets => ->(t) { t.to_date.beginning_of_month }
        }.each do |buckets, bucket_of|
          buckets.each do |bucket|
            newest = dated.detect { |b| bucket_of.(times[b]) == bucket }
            keep << newest if newest
          end
        end

        disposable = backups - keep
        Rails.logger.debug "Keep backups: #{keep.uniq * ', '}"
        Rails.logger.debug "Dispose backups: #{disposable * ', '}"
        disposable
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