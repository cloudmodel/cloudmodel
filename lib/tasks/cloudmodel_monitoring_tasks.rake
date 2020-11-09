require_relative "../../app/models/cloud_model/monitoring/base_checks"
require_relative "../../app/models/cloud_model/monitoring/mixins/sysinfo_checks_mixin"
require_relative "../../app/models/cloud_model/monitoring/host_checks"
require_relative "../../app/models/cloud_model/monitoring/guest_checks"
require_relative "../../app/models/cloud_model/monitoring/service_checks"
require_relative "../../app/models/cloud_model/monitoring/lxd_custom_volume_checks"

def handle_cloudmodel_monitoring_exception subject, host, indent
  begin
    issue = subject.item_issues.find_or_initialize_by key: :check_crashed, resolved_at: nil

    yield
  rescue Exception => e
    prefix = ''
    if host
      if host.is_a? String
        prefix = "[#{host}] "
      else
        prefix = "[#{host.name}] "
      end
    end
    puts "#{prefix}#{(' ' * indent)}\e[33m! Check for #{subject} crashed\e[39m"
    issue.severity = :warning
    issue.message = "#{e.message}\n\n#{e.backtrace * "\n"}"
    issue.value = e.message
    issue.save
    return false
  end
  issue.resolved_at = Time.now
  issue.save if issue.persisted?
  return true
end

namespace :cloudmodel do
  namespace :monitoring do
    desc "Check monitoring"
    task :check => [:environment] do
      threads = []

      CloudModel::Host.scoped.each do |host|
        unless [:booting, :not_started].include?(host.deploy_state)
          puts "[_Monitoring_] Treading #{host}"
          threads << Thread.new do
            Rails.application.executor.wrap do
              handle_cloudmodel_monitoring_exception host, host, 2 do
                if CloudModel::Monitoring::HostChecks.new(host).check
                  host.guests.each do |guest|
                    handle_cloudmodel_monitoring_exception guest, host, 4 do
                      if CloudModel::Monitoring::GuestChecks.new(guest).check
                        guest.lxd_custom_volumes.each do |lxd_custom_volume|
                          handle_cloudmodel_monitoring_exception lxd_custom_volume, host, 6 do
                            CloudModel::Monitoring::LxdCustomVolumeChecks.new(lxd_custom_volume).check
                          end
                        end
                        guest.services.each do |service|
                          handle_cloudmodel_monitoring_exception service, host, 6 do
                            CloudModel::Monitoring::ServiceChecks.new(service).check
                          end
                        end
                      end
                    end
                  end
                end
                puts "[#{host.name}] Done."
              end
            end
          end
        end
      end
      threads.each(&:join)

      CloudModel::MongodbReplicationSet.scoped.each do |replication_set|
        handle_cloudmodel_monitoring_exception replication_set, '_Mongo Repl_', 2 do
          CloudModel::Monitoring::MongodbReplicationSetChecks.new(replication_set).check
        end
      end

      puts "[_Monitoring_] Done."
    end
  end
end