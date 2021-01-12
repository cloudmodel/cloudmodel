module CloudModel
  module Workers
    module Services
      class MariadbWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          target = '/var/lib/mysql'

          puts "        Write mariadb config"
          @host.sftp.file.open("#{@guest.deploy_path.shellescape}/etc/mysql/mariadb.conf.d/50-server.cnf", 'w') do |f|
            f.write render("/cloud_model/guest/etc/mysql/mariadb.conf.d/50-server.cnf", guest: @guest, model: @model)
          end
        end

        def auto_restart
          true
        end

        def auto_start
          mkdir_p overlay_path
          #render_to_remote "/cloud_model/guest/etc/systemd/system/mariadb.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"
          super
        end
      end
    end
  end
end