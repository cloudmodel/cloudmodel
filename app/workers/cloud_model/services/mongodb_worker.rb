module CloudModel
  module Services
    class MongodbWorker < CloudModel::Services::BaseWorker
      def write_config
        target = '/var/lib/mongodb'
      
        puts "        Write mongodb config"
        @host.sftp.file.open(File.expand_path("etc/mongodb.conf", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/mongodb.conf", guest: @guest, model: @model)
        end
      
        chroot @guest.deploy_path, "chown -R 101:root #{target.shellescape}"
        log_dir_path = "/var/log/mongodb/"
        mkdir_p "#{@guest.deploy_path}#{log_dir_path}"
        @host.exec "chmod -R 2770 #{@guest.deploy_path}#{log_dir_path}"
        chroot @guest.deploy_path, "chown -R mongodb:root #{log_dir_path}"
      end
    end
  end
end