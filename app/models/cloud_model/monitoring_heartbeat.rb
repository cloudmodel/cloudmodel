module CloudModel
  # One record per admin host running the monitoring: when its current cycle
  # started, when its last cycle finished and how long it took.
  #
  # Two things hang on it. A cycle that hangs stops updating it, which the
  # other admins notice ({Monitoring::HeartbeatChecks}) — the monitoring
  # cannot report its own absence. And with more than one admin running the
  # monitoring, each one starts its cycle half a period after the other
  # ({.stagger_delay}), so the fleet is looked at twice per period instead of
  # twice at the same moment.
  class MonitoringHeartbeat
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute [rw] host_name
    #   @return [String] the admin host the monitoring runs on
    field :host_name, type: String
    # @!attribute [rw] started_at
    #   @return [Time] start of the current (or last) cycle
    field :started_at, type: Time
    # @!attribute [rw] finished_at
    #   @return [Time] end of the last completed cycle
    field :finished_at, type: Time
    # @!attribute [rw] duration
    #   @return [Float] seconds the last completed cycle took
    field :duration, type: Float

    index({ host_name: 1 }, { unique: true })

    # Seconds a cycle is assumed to take before a host has completed one.
    DEFAULT_DURATION = 600

    # @return [String] name of the host this process runs on
    def self.own_host_name
      Socket.gethostname
    end

    # Records the start of a cycle for this host.
    # @param started_at [Time]
    def self.start! started_at: Time.now
      find_or_initialize_by(host_name: own_host_name).update! started_at: started_at
    rescue => e
      Rails.logger.warn "MonitoringHeartbeat: #{e.class}: #{e.message}"
    end

    # Records the end of a cycle for this host.
    # @param started_at [Time]
    def self.beat! started_at:
      now = Time.now
      find_or_initialize_by(host_name: own_host_name).update! started_at: started_at, finished_at: now, duration: now - started_at
    rescue => e
      Rails.logger.warn "MonitoringHeartbeat: #{e.class}: #{e.message}"
    end

    # Heartbeats of other hosts that were active within `within`.
    # @return [Mongoid::Criteria]
    def self.peers within: 1.week, now: Time.now
      where(:host_name.ne => own_host_name, :updated_at.gte => now - within)
    end

    # Other hosts' heartbeats whose last completed cycle is older than
    # `max_age` (or that never completed one), among those active within
    # the last week — the watchdog's input.
    # @return [Array<CloudModel::MonitoringHeartbeat>]
    def self.stale max_age: 3.hours, now: Time.now
      peers(now: now).to_a.select { |h| h.stale? max_age: max_age, now: now }
    end

    # @return [Boolean] whether the last completed cycle is older than `max_age`
    def stale? max_age: 3.hours, now: Time.now
      finished_at.nil? or finished_at < now - max_age
    end

    # Seconds this host should wait before starting a cycle so that its
    # start falls half a period after the most recent start of another
    # active host. A period is the longest known cycle plus the pause the
    # service unit makes between cycles. Waiting is capped at half a period:
    # once past the middle, starting now is never worse than waiting longer
    # — the other host will then be the one to shift.
    # @param pause [Numeric] seconds between cycles (RestartSec of the unit)
    # @return [Float] seconds to wait, 0 when alone or already in place
    def self.stagger_delay pause: CloudModel.config.monitoring_restart_pause, now: Time.now
      own = where(host_name: own_host_name).first
      durations = peers(now: now).to_a.map(&:duration).compact
      durations << own.duration if own&.duration
      durations << DEFAULT_DURATION if durations.empty?
      period = durations.max + pause

      # Only a host that started a cycle within the last two periods is
      # running; aligning to one that stopped would delay every cycle.
      peer = peers(now: now).where(:started_at.gte => now - 2 * period).to_a.max_by(&:started_at)
      return 0.0 unless peer

      phase = (now - peer.started_at) % period
      delay = (period / 2.0 - phase) % period
      delay > period / 2.0 ? 0.0 : delay
    end
  end
end
