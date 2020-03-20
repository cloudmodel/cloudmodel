namespace :cloudmodel do
  namespace :monitoring do
    desc "Check monitoring"
    task :check => [:environment] do
      CloudModel::Host.all.each do |host|
        CloudModel::HostChecks.new(host).check
        host.guests.each do |guest|
          CloudModel::GuestChecks.new(host, guest).check
          guest.lxd_custom_volumes.each do |lxd_custom_volume|
            CloudModel::LxdCustomVolumeChecks.new(host, guest, lxd_custom_volume).check
          end
        end
      end
    end
  end
end