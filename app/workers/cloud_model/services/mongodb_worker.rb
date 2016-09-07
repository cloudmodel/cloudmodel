module CloudModel
  module Services
    class MongodbWorker < CloudModel::Services::BaseWorker
      def write_config
        target = '/var/lib/mongodb'
      
        puts "        Write mongodb config"
        @host.sftp.file.open("#{@guest.deploy_path.shellescape}/etc/mongodb.conf", 'w') do |f|
          f.write render("/cloud_model/guest/etc/mongodb.conf", guest: @guest, model: @model)
        end
      end
      
      def auto_restart
        true
      end
      
      def auto_start
        super
        render_to_remote "/cloud_model/guest/etc/systemd/system/mongodb.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"
      end
    end
  end
end