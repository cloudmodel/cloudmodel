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
      end

      # Begin a fresh console for a new flow run.
      def restart_live_log
        @live_log_buffer = +''
        @live_log_flushed_at = nil
        self.live_log = ''
        self.live_log_started_at = Time.now
        set live_log: '', live_log_started_at: live_log_started_at
      rescue => e
        Rails.logger.warn "Could not restart live log: #{e.message}"
      end

      def append_live_log text
        @live_log_buffer = "#{@live_log_buffer}#{text}"
        if @live_log_flushed_at.nil? || Time.now - @live_log_flushed_at >= FLUSH_INTERVAL
          flush_live_log
        end
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
