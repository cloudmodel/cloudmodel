module CloudModel
  module Workers
    module Components
      class NginxComponentWorker < BaseComponentWorker
        def _prepare_passenger_repository build_path
          chroot! build_path, "apt-get install dirmngr gnupg -y", "Failed to install key management"
          chroot! build_path, "apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 561F9B9CAC40B2F7", "Failed to add fusion key"
          render_to_remote "/cloud_model/guest/etc/apt/sources.list.d/passenger.list", "#{build_path}/etc/apt/sources.list.d/passenger.list", 600, template: @template
        end

        def _prepare_certbot_repository build_path
          chroot! build_path, "add-apt-repository universe -y", "Failed to add universe repository"
          chroot! build_path, "add-apt-repository ppa:certbot/certbot -y", "Failed to add certbot repository"
          chroot! build_path, "apt-get update", "Failed to update packages"
        end

        def build build_path
          ### TODO; Test build in nginx
          ### if running: remove /cloud_model/guest/etc/apt/sources.list.d/passenger.list
          ### if not running: fix sources
          _prepare_passenger_repository build_path


          chroot! build_path, "apt-get update", "Failed to update packages"
          if CloudModel.debian_name(@template.os_version) == 'Bionic Beaver'
            # Needs to install certbot via PPA on Ubuntu 18.04
            # Add certbot for letsencrypt support
            _prepare_certbot_repository build_path

            chroot! build_path, "apt-get install nginx-extras libnginx-mod-http-passenger certbot python-certbot-nginx -y", "Failed to install nginx+passenger+certbot"
          else
            chroot! build_path, "apt-get update", "Failed to update packages"
            chroot! build_path, "apt-get install nginx-extras libnginx-mod-http-passenger certbot python3-certbot-nginx -y", "Failed to install nginx+passenger+certbot"
          end
          log_dir_path = "/var/log/nginx"
          @host.exec! "rm -rf #{build_path}#{log_dir_path}", "Failed to clear log dir"
        end
      end
    end
  end
end