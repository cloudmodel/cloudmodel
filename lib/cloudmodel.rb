require 'mongoid-grid_fs'
require "cloud_model/config"
require "cloud_model/build_zfs_volume"
require "cloud_model/engine"
require "cloud_model/monitoring"
#require "cloud_model/call_rake"
require "cloud_model/execution_exception"

module CloudModel
  # Build states a template can rest in (finished, failed, not_started) —
  # matches buildable_build_states on the template models. Single source for
  # TemplateCleanup and the ZFS build claim.
  TERMINAL_BUILD_STATE_IDS = [0xf0, 0xf1, 0xff].freeze

  def self.config
    @config ||= CloudModel::Config.new
  end

  def self.configure(&block)
    config.configure(&block)
  end

  # Run +block+ for each item, up to +concurrency+ at a time, and wait for all.
  # Used to overlap backups (which mostly wait on mongodump / zfs send). Falls
  # back to a plain sequential each for concurrency <= 1 or a single item.
  # @return the items
  def self.parallel_each(items, concurrency: config.backup_concurrency, &block)
    items = items.to_a
    return items.each(&block) if concurrency.to_i <= 1 || items.size <= 1

    queue = Queue.new
    items.each { |item| queue << item }

    [concurrency.to_i, items.size].min.times.map do
      Thread.new do
        loop do
          item = begin
            queue.pop(true)
          rescue ThreadError
            break
          end
          block.call item
        end
      end
    end.each(&:join)

    items
  end

  # The BackupRun of the currently executing backup rake task, when any —
  # backup_log mirrors its lines into it for the admin live console.
  # Process-global on purpose: all backup worker threads feed the same run.
  def self.current_backup_run
    @current_backup_run
  end

  # The subject whose live console (Mixins::LiveLog#with_live_log) is
  # currently capturing — BaseWorker#run_steps reports its numbered steps to
  # it so the admin UI can show "building — (3/12) Install basic utils".
  def self.current_live_log_subject
    @current_live_log_subject
  end

  def self.current_live_log_subject= subject
    @current_live_log_subject = subject
  end

  def self.current_backup_run= run
    @current_backup_run = run
  end

  # Progress line for backup runs: printed to stdout (visible in the rake
  # console and cron mail), mirrored to the Rails log and — during a tracked
  # run — into the BackupRun's live log. Prefixed with the current thread's
  # backup label (guest / replica set name), so interleaved lines of parallel
  # backups stay attributable.
  def self.backup_log message
    label = Thread.current[:cloud_model_backup_label]
    line = label ? "[#{label}] #{message}" : message
    $stdout.puts line
    $stdout.flush
    current_backup_run&.append_log "#{line}\n"
    Rails.logger.info line
  end

  # Tag all {backup_log} output of the current thread with +label+ while the
  # block runs — one label per parallel_each worker item.
  def self.with_backup_label label
    previous = Thread.current[:cloud_model_backup_label]
    Thread.current[:cloud_model_backup_label] = label
    yield
  ensure
    Thread.current[:cloud_model_backup_label] = previous
  end

  # Run a shell command, streaming its combined stdout+stderr line by line
  # through {backup_log} (mongodump & co. report progress on stderr).
  # @return [Boolean] whether the command succeeded
  def self.backup_exec command
    Rails.logger.debug command
    IO.popen(command, err: [:child, :out]) do |io|
      io.each_line { |line| backup_log line.chomp }
    end
    $?.success?
  end

  def self.log_exception e
    message = "CloudModel: uncaught #{e.class} exception while handling connection: #{e.message}"
    trace = "Stack trace:\n#{e.backtrace.to_a.map {|l| "  #{l}\n"}.join}"

    Rails.logger.error message
    Rails.logger.error trace

    # Also surface the exception and backtrace on stderr so a human running a
    # console, rake task, or production process sees what failed directly,
    # not only buried in the log. Tests silence this via a global stub in
    # spec_helper to keep spec output clean.
    warn message
    warn trace
  end

  def self.debian_names
    {
      'ubuntu-18.04' => 'Bionic Beaver',
      'ubuntu-20.04' => 'Focal Fossa',
      'ubuntu-22.04' => 'Jammy Jellyfish',
      'ubuntu-24.04' => 'Noble Numbat',
      'debian-11'    => 'Bullseye',
      'debian-12'    => 'Bookworm',
      'debian-13'    => 'Trixie',
      'debian-14'    => 'Forky'
    }
  end

  def self.debian_name version
    debian_names[version.match(/\A.*-[0-9]+(.[0-9]+)?/)[0]]
  end

  def self.debian_short_name version
    debian_name(version).split.first.downcase
  end
end