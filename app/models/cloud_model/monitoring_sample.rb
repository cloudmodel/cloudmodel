module CloudModel
  # A time-series sample of numeric monitoring metrics for any model that
  # includes {Mixins::HasIssues} (hosts, guests, services, …).
  #
  # Samples are recorded by the monitoring checks (see
  # {Monitoring::BaseChecks#record_sample}) every check cycle at the `raw`
  # resolution. A periodic rollup ({.rollup!}) consolidates them into coarser
  # `hour` and `day` resolutions so long-time graphs stay cheap to query.
  #
  # Round-robin retention is handled by a TTL index on {#expires_at}: each
  # resolution keeps data for the window configured in
  # {CloudModel::Config#monitoring_sample_retention}, after which MongoDB
  # expires the documents automatically.
  class MonitoringSample
    include Mongoid::Document
    include Mongoid::Timestamps

    # Ordered from finest to coarsest. Each step rolls up into the next.
    RESOLUTIONS = %w(raw hour day).freeze

    # Bucket length per non-raw resolution.
    INTERVALS = { 'hour' => 1.hour, 'day' => 1.day }.freeze

    # @!attribute [rw] subject
    #   @return [Object] the monitored model this sample belongs to (polymorphic)
    belongs_to :subject, optional: true, polymorphic: true

    # @!attribute [rw] resolution
    #   @return [String] one of {RESOLUTIONS} (`raw`, `hour`, `day`)
    field :resolution, type: String, default: 'raw'

    # @!attribute [rw] ref_at
    #   @return [Time] timestamp of the sample; for rollups the start of the bucket
    field :ref_at, type: Time

    # @!attribute [rw] metrics
    #   @return [Hash{String=>Float}] flat metric name → numeric value map
    field :metrics, type: Hash, default: {}

    # @!attribute [rw] expires_at
    #   @return [Time] when MongoDB should drop this sample (TTL retention)
    field :expires_at, type: Time

    index subject_type: 1, subject_id: 1, resolution: 1, ref_at: 1
    index({ expires_at: 1 }, { expire_after_seconds: 0 })

    # Record a raw sample for the given subject.
    #
    # @param subject [Object] a model including {Mixins::HasIssues}
    # @param metrics [Hash] flat metric name → numeric value map
    # @param at [Time] timestamp of the measurement
    # @return [CloudModel::MonitoringSample, nil] the stored sample, or nil when there is nothing to store
    def self.record! subject, metrics, at: Time.now
      metrics = (metrics || {}).reject { |_k, v| v.nil? }
      return nil if metrics.blank?

      create!(
        subject: subject,
        resolution: 'raw',
        ref_at: at,
        metrics: metrics,
        expires_at: at + retention_for('raw')
      )
    end

    # Retention window (as a duration) for the given resolution.
    # @return [ActiveSupport::Duration]
    def self.retention_for resolution
      CloudModel.config.monitoring_sample_retention[resolution.to_sym]
    end

    # Consolidate finer resolutions into coarser ones. Idempotent: only the
    # most recent buckets are recomputed so late-arriving raw data is folded in
    # without rewriting the whole history.
    def self.rollup!
      rollup_resolution! 'raw', 'hour', recompute: 2.hours
      rollup_resolution! 'hour', 'day', recompute: 2.days
    end

    # Roll `from` resolution samples up into `to` resolution buckets.
    #
    # @param from [String] source resolution
    # @param to [String] target resolution
    # @param recompute [ActiveSupport::Duration] how far back to recompute buckets
    def self.rollup_resolution! from, to, recompute:
      interval = INTERVALS[to]
      retention = retention_for to
      since = Time.now - recompute

      groups = Hash.new { |h, k| h[k] = [] }
      where(resolution: from).gte(ref_at: since).each do |sample|
        bucket = bucket_time sample.ref_at, interval
        groups[[sample.subject_type, sample.subject_id, bucket]] << sample.metrics
      end

      groups.each do |(subject_type, subject_id, bucket), metrics_list|
        averaged = average_metrics metrics_list

        where(
          subject_type: subject_type,
          subject_id: subject_id,
          resolution: to,
          ref_at: bucket
        ).find_one_and_update(
          { '$set' => { metrics: averaged, expires_at: bucket + retention } },
          upsert: true
        )
      end
    end

    # Floor a timestamp to the start of its bucket.
    # @return [Time]
    def self.bucket_time time, interval
      seconds = interval.to_i
      Time.at((time.to_i / seconds) * seconds).utc
    end

    # Average each metric across a list of metric hashes, ignoring missing keys.
    # @return [Hash{String=>Float}]
    def self.average_metrics metrics_list
      sums = Hash.new 0.0
      counts = Hash.new 0

      metrics_list.each do |metrics|
        metrics.each do |key, value|
          next unless value.is_a? Numeric
          sums[key] += value.to_f
          counts[key] += 1
        end
      end

      sums.each_with_object({}) do |(key, sum), result|
        result[key] = sum / counts[key]
      end
    end
  end
end
