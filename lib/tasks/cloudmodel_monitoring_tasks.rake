#require_relative "../../app/models/cloud_model/monitoring"

namespace :cloudmodel do
  namespace :monitoring do
    desc "Check monitoring (STAGGER=0 skips the wait that interleaves cycles with other monitoring hosts)"
    task :check => [:environment] do
      # With another admin host running the monitoring, start half a period
      # after it did, so the fleet is checked twice per period.
      if ENV['STAGGER'] != '0' and (delay = CloudModel::MonitoringHeartbeat.stagger_delay) > 0
        puts "[_Monitoring_] Waiting #{delay.round} s to interleave with the other monitoring host(s)"
        sleep delay
      end

      begin
        CloudModel::Monitoring.check
      ensure
        # Consolidate the RRD even if the check run failed: Monitoring.check now
        # tracks per-group failures as ItemIssues instead of raising, but the
        # rollup must run regardless so the monitoring history stays consistent
        # (and doesn't leave gaps that a later run has to backfill).
        CloudModel::MonitoringSample.rollup!
      end
      puts "[_Monitoring_] Done."
    end

    desc "Rewrite stored MongoDB service samples to the current gauge set (one-off after the sampler stopped flattening all of serverStatus). Dry run unless CONFIRM=1."
    task :rewrite_mongodb_samples => [:environment] do
      puts CloudModel::MonitoringSample.rewrite_mongodb_samples!(confirm: ENV['CONFIRM'] == '1')
    end

    desc "Consolidate monitoring samples into coarser resolutions"
    task :rollup => [:environment] do
      CloudModel::MonitoringSample.rollup!
      puts "[_Monitoring_] Rollup done."
    end
  end
end