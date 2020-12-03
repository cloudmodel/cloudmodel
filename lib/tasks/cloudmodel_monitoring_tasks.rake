require_relative "../../app/models/cloud_model/monitoring"

namespace :cloudmodel do
  namespace :monitoring do
    desc "Check monitoring"
    task :check => [:environment] do
      CloudModel::Monitoring.check
      puts "[_Monitoring_] Done."
    end
  end
end