module CloudModel
  # One record per backup run (rake cloudmodel:backup / guest:backup_all):
  # carries the live console log and subject progress for the admin UI —
  # the same lines CloudModel.backup_log prints to stdout.
  #
  # Log appends are buffered in process (parallel workers stream mongodump
  # output) and flushed to the DB at most once per FLUSH_INTERVAL; the log is
  # kept as a rolling tail of LOG_LIMIT characters.
  class BackupRun
    include Mongoid::Document
    include Mongoid::Timestamps

    field :started_at, type: Time
    field :finished_at, type: Time
    field :success, type: Mongoid::Boolean
    field :log, type: String, default: ''
    field :total_subjects, type: Integer, default: 0
    field :finished_subjects, type: Integer, default: 0

    index({started_at: -1})

    LOG_LIMIT = 512 * 1024
    FLUSH_INTERVAL = 1 # second
    KEEP_RUNS = 30

    # All log appenders share one lock; contention is trivial (a handful of
    # backup workers), and a shared lock avoids lazy-init races.
    LOG_MUTEX = Mutex.new

    # Machine-wide backup lock file. Concurrent backup runs (nightly cron,
    # manual rake, single-subject delayed jobs) write into the same target
    # datasets and dump dirs — they must never interleave. The rake task
    # flocks this non-blocking (aborts), {#with_file_lock} waits.
    def self.lock_file_path
      "#{CloudModel.config.data_directory}/backup_run.lock"
    end

    # Hold the machine-wide backup lock while the block runs, waiting for a
    # running backup (e.g. the nightly rake run) to finish first.
    def self.with_file_lock
      lock = File.open lock_file_path, File::CREAT, 0o644
      lock.flock File::LOCK_EX
      yield
    ensure
      if lock
        lock.flock File::LOCK_UN
        lock.close
      end
    end

    # Begin a new run: close stale unfinished runs (killed processes never
    # reach finish!) and prune old ones.
    # @return [CloudModel::BackupRun]
    def self.start! total_subjects:
      where(finished_at: nil).each do |stale|
        stale.append_log "Run superseded by a newer one — marking as failed (process killed?)\n"
        stale.finish! success: false
      end
      desc(:started_at).skip(KEEP_RUNS).each(&:delete)
      create! started_at: Time.now, total_subjects: total_subjects
    end

    # @return [CloudModel::BackupRun, nil] the most recent run, running or not
    def self.latest
      desc(:started_at).first
    end

    def active?
      finished_at.nil?
    end

    # @return [Integer] 0..100
    def progress_percent
      return 0 if total_subjects.to_i <= 0
      [(finished_subjects * 100.0 / total_subjects).round, 100].min
    end

    # Thread-safe buffered append (flushed at most every FLUSH_INTERVAL).
    def append_log line
      LOG_MUTEX.synchronize do
        @log_buffer = "#{@log_buffer}#{line}"
        flush_log_locked if @last_flush.nil? || Time.now - @last_flush >= FLUSH_INTERVAL
      end
    end

    def flush_log
      LOG_MUTEX.synchronize { flush_log_locked }
    end

    # Progress tick — one subject (guest or replica set) processed.
    def subject_finished!
      inc finished_subjects: 1
    end

    def finish! success:
      flush_log
      update_attributes finished_at: Time.now, success: success
    end

    private

    def flush_log_locked
      return if @log_buffer.nil? || @log_buffer.empty?
      combined = "#{log}#{@log_buffer}"
      if combined.length > LOG_LIMIT
        combined = "… (truncated)\n#{combined.last(LOG_LIMIT)}"
      end
      self.log = combined
      set log: combined # only the log field — never clobber concurrent incs
      @log_buffer = +''
      @last_flush = Time.now
    end
  end
end
