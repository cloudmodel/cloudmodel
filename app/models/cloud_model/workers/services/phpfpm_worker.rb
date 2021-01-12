module CloudModel
  module Workers
    module Services
      class PhpfpmWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          puts "        Write PHP FPM config"
          render_to_remote "/cloud_model/guest/etc/php/7.2/fpm/pool.d/www.conf", "#{@guest.deploy_path}/etc/php/7.2/fpm/pool.d/www.conf", guest: @guest, model: @model
          chroot! @guest.deploy_path, "groupadd -f -r -g 1001 www && id -u www || useradd -c 'added by cloud_model for nginx' -d /var/www -s /bin/bash -r -g 1001 -u 1001 www", "Failed to add www user"
        end

        def service_name
          "php-fpm"
        end

        def auto_restart
          true
        end
      end
    end
  end
end