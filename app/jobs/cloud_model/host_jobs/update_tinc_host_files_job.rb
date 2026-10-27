module CloudModel
  module HostJobs
    # Brings the tinc host files of every deployed host in line with the
    # VPN clients and hosts in the database: new and changed nodes get their
    # file, files of deleted nodes are moved aside, tincd reloads. Enqueued
    # when a VPN client is created, changed or deleted.
    class UpdateTincHostFilesJob < CloudModel::BaseJob
      def perform
        failures = []
        CloudModel::Host.tinc_peers_of(nil).each do |host|
          begin
            removed = CloudModel::Workers::HostWorker.new(host).update_tinc_host_files
            Rails.logger.info "tinc host files updated on #{host.name}#{"; moved aside: #{removed * ', '}" unless removed.empty?}"
          rescue => e
            failures << host.name
            CloudModel.log_exception e
          end
        end
        raise "Updating tinc host files failed on #{failures * ', '}" unless failures.empty?
      end
    end
  end
end
