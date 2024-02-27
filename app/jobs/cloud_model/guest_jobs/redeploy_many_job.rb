module CloudModel
  module GuestJobs
    class RedeployManyJob < CloudModel::BaseJob
      def perform(guest_ids)
        guests_by_hosts = {}

        CloudModel::Guest.where(:id.in => guest_ids).to_a.each do |guest|
          if guest.deploy_state == :pending
            guests_by_hosts[guest.host_id] ||= []
            guests_by_hosts[guest.host_id] << guest
          end
        end

        guests_by_hosts.each do |host_id, guests|
          # TODO: Multithread redeploy (thread per host)
          puts "** Deploy on Host #{host_id}"
          guests.each do |guest|
            puts "=> Redeploy Guest '#{guest.name}'"
            guest_worker = CloudModel::Workers::GuestWorker.new guest
            guest_worker.redeploy
          end
        end
      end
    end
  end
end