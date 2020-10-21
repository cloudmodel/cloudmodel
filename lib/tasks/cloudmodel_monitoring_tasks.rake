namespace :cloudmodel do
  namespace :monitoring do
    desc "Check monitoring"
    task :check => [:environment] do
      CloudModel::Host.scoped.each do |host|
        unless [:booting, :not_started].include?(host.deploy_state)
          CloudModel::Monitoring::HostChecks.new(host).check
          host.guests.each do |guest|
            unless [:booting, :not_started].include?(guest.deploy_state)
              CloudModel::Monitoring::GuestChecks.new(guest).check
              guest.lxd_custom_volumes.each do |lxd_custom_volume|
                CloudModel::Monitoring::LxdCustomVolumeChecks.new(lxd_custom_volume).check
              end
              guest.services.each do |service|
                CloudModel::Monitoring::ServiceChecks.new(service).check
              end
            end
          end
        end
      end
      puts "Done."
    end
  end
end