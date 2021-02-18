module CloudModel
  module Workers
    module Services
      class PhpfpmWorker < CloudModel::Workers::Services::BaseWorker
        def patch_php_ini key, value
          chroot! @guest.deploy_path, "sed -i 's/#{key} = .*/#{key} = #{value}/' /etc/php/#{CloudModel.config.php_version}/fpm/php.ini", "Failed to config PHP option #{key}"
        end

        def write_config
          comment_sub_step "Write PHP FPM config"
          render_to_remote "/cloud_model/guest/etc/php/fpm/pool.d/www.conf", "#{@guest.deploy_path}/etc/php/#{CloudModel.config.php_version}/fpm/pool.d/www.conf", guest: @guest, model: @model
          render_to_remote "/cloud_model/guest/etc/php/fpm/conf.d/30-msmtp.ini", "#{@guest.deploy_path}/etc/php/#{CloudModel.config.php_version}/fpm/conf.d/30-msmtp.ini", guest: @guest, model: @model

          # Patch php.ini
          patch_php_ini :upload_max_filesize, "#{@model.php_upload_max_filesize}M"

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