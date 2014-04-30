module CloudModel
  module Services
    class MongodbWorker < CloudModel::Services::BaseWorker
      def write_config
        target = '/var/lib/mongodb'
      
        puts "        Write mongodb config"
        @host.ssh_connection.sftp.file.open(File.expand_path("etc/conf.d/mongodb", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/conf.d/mongodb", guest: @guest, model: @model)
        end
      
        @host.exec "chown -R 101:root #{@guest.deploy_path.shellescape}#{target.shellescape}"
        log_dir_path = "#{@guest.deploy_path}/var/log/mongodb/"
        mkdir_p log_dir_path
        @host.exec "chmod -R 2770 #{log_dir_path}"
        @host.exec "chown -R 101:root #{log_dir_path}"
      end
    end
  end
end