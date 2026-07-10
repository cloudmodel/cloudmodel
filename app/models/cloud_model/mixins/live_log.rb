module CloudModel
  module Mixins
    # Rolling live console log for long-running flows (deploys, template and
    # image builds), streamed by the admin UI like the backup console. The
    # workers' stdout is teed in via {CloudModel::BaseJob#with_live_log}.
    #
    # Appends are buffered in process (chatty worker output) and flushed to
    # the DB at most once per FLUSH_INTERVAL; the log is kept as a rolling
    # tail of LOG_LIMIT characters. Single-writer by design — the flows run
    # one at a time in the delayed_job worker.
    module LiveLog
      LOG_LIMIT = 512 * 1024
      FLUSH_INTERVAL = 1 # second

      def self.included(base)
        base.field :live_log, type: String, default: ''
        base.field :live_log_started_at, type: Time
        # Current numbered step of the running flow (see BaseWorker#run_steps)
        # — "(3/12) Install basic utils" in the admin state displays. Kept on
        # failure (shows WHERE it failed), cleared on success and restart.
        base.field :live_log_step, type: String
        base.field :live_log_step_counter, type: String
        base.field :live_log_step_total, type: Integer
      end

      # Begin a fresh console for a new flow run.
      def restart_live_log
        @live_log_pending_restart = false
        @live_log_buffer = +''
        @live_log_flushed_at = nil
        self.live_log = ''
        self.live_log_started_at = Time.now
        self.live_log_step = self.live_log_step_counter = self.live_log_step_total = nil
        set live_log: '', live_log_started_at: live_log_started_at,
            live_log_step: nil, live_log_step_counter: nil, live_log_step_total: nil
      rescue => e
        Rails.logger.warn "Could not restart live log: #{e.message}"
      end

      # Clear the console and step badge the moment a new flow is ENQUEUED —
      # a pending flow still showing the previous run's failed step ("Geplant
      # — (2/11) …") reads as if it were already mid-flight. The job itself
      # still does its lazy restart_live_log on first output (with_live_log),
      # which also covers flows run without going through an enqueue method.
      def reset_live_log
        self.live_log = ''
        self.live_log_step = self.live_log_step_counter = self.live_log_step_total = nil
        set live_log: '', live_log_step: nil, live_log_step_counter: nil, live_log_step_total: nil
      rescue => e
        Rails.logger.warn "Could not reset live log: #{e.message}"
      end

      # First real activity of a pending flow performs the deferred restart
      # (see with_live_log).
      def ensure_live_log_started
        return unless @live_log_pending_restart
        @live_log_pending_restart = false
        restart_live_log
      end

      # Record the flow's current numbered step (nil clears it).
      def set_live_log_step step, counter: nil, total: nil
        ensure_live_log_started
        self.live_log_step = step
        self.live_log_step_counter = counter
        self.live_log_step_total = total
        set live_log_step: step, live_log_step_counter: counter, live_log_step_total: total
      rescue => e
        Rails.logger.warn "Could not record live log step: #{e.message}"
      end

      def append_live_log text
        ensure_live_log_started
        @live_log_buffer = "#{@live_log_buffer}#{text}"
        if @live_log_flushed_at.nil? || Time.now - @live_log_flushed_at >= FLUSH_INTERVAL
          flush_live_log
        end
      end

      # Runs the block with $stdout captured into this subject's live console
      # — the one shared mechanism behind every deploy/build console in the
      # admin UI. By default the console stays quiet (watch the log on the
      # web); verbose: true additionally passes the output through to stdout
      # (interactive console runs, the delayed_job logfile).
      def with_live_log verbose: false
        # Restart lazily on the FIRST output: delayed_job retries a raised
        # flow, and the retry immediately refuses to run (state already
        # failed) — an eager restart would wipe the previous attempt's log,
        # which is exactly what you need to debug the failure.
        @live_log_pending_restart = true
        previous_subject = CloudModel.current_live_log_subject
        CloudModel.current_live_log_subject = self
        CloudModel::StdoutTee.capture ->(text) { append_live_log text }, passthrough: verbose do
          yield
        rescue Exception => e
          # The failure reason belongs in the console too — workers that
          # don't catch the error would otherwise leave the log ending
          # mid-step while the message only reaches the *_last_issue field.
          append_live_log "\n#{e.class}: #{e.message}\n"
          raise
        end
        # The step fields stay as they are: the last step of a FAILED flow
        # shows where it failed; the state displays skip the step once the
        # flow finished successfully.
      ensure
        CloudModel.current_live_log_subject = previous_subject
        flush_live_log
      end

      def flush_live_log
        return if @live_log_buffer.nil? || @live_log_buffer.empty?
        combined = "#{live_log}#{@live_log_buffer}"
        if combined.length > LOG_LIMIT
          combined = "… (truncated)\n#{combined.last(LOG_LIMIT)}"
        end
        self.live_log = combined
        set live_log: combined # only this field — never clobber concurrent writes
        @live_log_buffer = +''
        @live_log_flushed_at = Time.now
      rescue => e
        # The console is bookkeeping — it must never fail the flow itself.
        Rails.logger.warn "Could not flush live log: #{e.message}"
      end
    end
  end
end
