#require_relative "../../app/models/cloud_model/monitoring"

namespace :cloudmodel do
  namespace :monitoring do
    desc "Check monitoring"
    task :check => [:environment] do
      CloudModel::Monitoring.check
      CloudModel::MonitoringSample.rollup!
      puts "[_Monitoring_] Done."
    end

    desc "Consolidate monitoring samples into coarser resolutions"
    task :rollup => [:environment] do
      CloudModel::MonitoringSample.rollup!
      puts "[_Monitoring_] Rollup done."
    end
  end
end