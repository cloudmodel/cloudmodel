module CloudModel
  module GuestJobs
    # Pushes the deploy keys to every running guest whose nginx service uses
    # one of the given SSH groups (all groups when none are given). Enqueued
    # when SSH keys or groups change, so removing a key takes effect without
    # a redeploy.
    class SyncAuthorizedKeysJob < CloudModel::BaseJob
      # @param group_ids [Array<String>, nil] SSH group ids; nil = all groups
      def perform(group_ids = nil)
        failures = []
        self.class.services_for(group_ids).each do |guest, service|
          begin
            result = service.worker.sync_authorized_keys
            next if [:unchanged, :skipped].include? result[:state]
            Rails.logger.info "authorized_keys on #{guest.name}: +#{result[:added] * ', '} -#{result[:removed] * ', '}"
          rescue => e
            failures << guest.name
            CloudModel.log_exception e
          end
        end
        raise "Syncing authorized_keys failed on #{failures * ', '}" unless failures.empty?
      end

      # Running guests and their nginx services with capistrano SSH groups,
      # optionally limited to services using one of the given groups.
      # @return [Array<Array(CloudModel::Guest, CloudModel::Services::Nginx)>]
      def self.services_for group_ids = nil
        ids = group_ids && group_ids.map { |id| BSON::ObjectId.from_string(id.to_s) }
        CloudModel::Guest.all.select { |guest| guest.up_state == :started }.flat_map do |guest|
          guest.services.select do |service|
            service.is_a?(CloudModel::Services::Nginx) and service.capistrano_ssh_group_ids.present? and
              (ids.nil? or (service.capistrano_ssh_group_ids & ids).any?)
          end.map { |service| [guest, service] }
        end
      end
    end
  end
end
