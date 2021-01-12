module CloudModel
  module Workers
    module Services
      class PhpfpmWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          puts "        Write PHP FPM config"
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