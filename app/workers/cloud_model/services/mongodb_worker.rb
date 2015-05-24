module CloudModel
  module Services
    class MongodbWorker < CloudModel::Services::BaseWorker
      def write_config
        target = '/var/lib/mongodb'

        puts "        Install mongodb"
        chroot! @guest.deploy_path, "apt-get install libreadline5 mongodb -y", "Failed to install mongodb"
      
        puts "        Write mongodb config"
        @host.sftp.file.open(File.expand_path("etc/mongodb.conf", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/mongodb.conf", guest: @guest, model: @model)
        end
      end
    end
  end
end