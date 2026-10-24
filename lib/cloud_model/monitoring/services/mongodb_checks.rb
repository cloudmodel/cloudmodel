module CloudModel
  module Monitoring
    module Services
      class MongodbChecks < CloudModel::Monitoring::Services::BaseChecks
        # The gauges worth a time series, by sample key, as paths into
        # serverStatus. The generic sampler flattened the whole serverStatus
        # (~2000 counters, ~120 KB per sample) — unreadable as charts and the
        # bulk of the monitoring_samples collection.
        SAMPLE_PATHS = {
          'db.connections'    => %w(connections current),
          'db.cursors'        => %w(metrics cursor open total),
          'db.queue_readers'  => %w(globalLock currentQueue readers),
          'db.queue_writers'  => %w(globalLock currentQueue writers),
          'db.active_readers' => %w(globalLock activeClients readers),
          'db.active_writers' => %w(globalLock activeClients writers),
          'db.resident_mb'    => %w(mem resident),
          'db.checkpoint_ms'  => ['wiredTiger', 'transaction', 'transaction checkpoint most recent time (msecs)']
        }.freeze
        CACHE_USED = ['wiredTiger', 'cache', 'bytes currently in the cache'].freeze
        CACHE_MAX  = ['wiredTiger', 'cache', 'maximum bytes configured'].freeze
        CACHE_DIRTY = ['wiredTiger', 'cache', 'tracked dirty bytes in the cache'].freeze

        def check
          do_check_for_errors_on data, {
            not_reachable: 'service reachable'
          }
        end

        def sample_metrics
          return {} unless data.is_a?(Hash) and data['connections']

          metrics = {}
          SAMPLE_PATHS.each do |key, path|
            value = data.dig(*path)
            metrics[key] = value.to_f if value.is_a?(Numeric)
          end
          used, max, dirty = data.dig(*CACHE_USED), data.dig(*CACHE_MAX), data.dig(*CACHE_DIRTY)
          metrics['db.cache_usage'] = (100.0 * used / max).round(2) if used.is_a?(Numeric) and max.is_a?(Numeric) and max > 0
          metrics['db.cache_dirty_mb'] = (dirty / 1024.0**2).round(1) if dirty.is_a?(Numeric)
          metrics
        end
      end
    end
  end
end
