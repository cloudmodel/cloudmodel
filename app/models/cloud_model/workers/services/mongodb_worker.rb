module CloudModel
  module Workers
    module Services
      class MongodbWorker < CloudModel::Workers::Services::BaseWorker
        def service_name
          "mongod"
        end

        def write_config
          target = '/var/lib/mongodb'

          comment_sub_step "Write mongodb config"
          @host.sftp.file.open("#{@guest.deploy_path.shellescape}/etc/mongod.conf", 'w') do |f|
            f.write render("/cloud_model/guest/etc/mongodb.conf", guest: @guest, model: @model)
          end
        end

        def auto_restart
          true
        end

        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/mongodb.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"
          super
        end
      end
    end
  end
end