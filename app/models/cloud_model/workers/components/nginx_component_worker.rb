module CloudModel
  module Workers
    module Components
      # Component worker that installs nginx with the Passenger module and certbot
      # into a guest template chroot.
      #
      # Adds the Phusion Passenger apt repository (and on Ubuntu 18.04 also the
      # certbot PPA), then installs `nginx-core`, `libnginx-mod-http-passenger`,
      # and `certbot` with the nginx plugin.
      class NginxComponentWorker < BaseComponentWorker
        def _prepare_passenger_repository build_path
          chroot! build_path, "apt-get install dirmngr gnupg -y", "Failed to install key management"
          # Phusion rotated its "automatic software signing" key in 2025 (the
          # repo Release files are signed with it since 2026-07); the old URL
          # still serves the expired 2013 key, so fetch the -2025 key — plus
          # the legacy one for older dists — into a signed-by keyring. The
          # former keyserver fetch via deprecated apt-key got the stale copy.
          chroot! build_path,
            "curl -sSLf https://oss-binaries.phusionpassenger.com/auto-software-signing-gpg-key-2025.txt | gpg --dearmor > /usr/share/keyrings/phusion.gpg && " \
            "curl -sSLf https://oss-binaries.phusionpassenger.com/auto-software-signing-gpg-key.txt | gpg --dearmor >> /usr/share/keyrings/phusion.gpg",
            "Failed to add phusion signing key"
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
            # Passenger >= 6.1.7 pins nginx-core (the flavors conflict, so
            # nginx-extras is out); headers-more comes as its own dynamic
            # module package instead (more_clear_headers in cloudmodel.conf).
            chroot! build_path, "apt-get install nginx-core libnginx-mod-http-headers-more-filter libnginx-mod-http-passenger certbot python3-certbot-nginx python3-venv python3-pip -y", "Failed to install nginx+passenger+certbot+python3"
          end
          log_dir_path = "/var/log/nginx"
          @host.exec! "rm -rf #{build_path}#{log_dir_path}", "Failed to clear log dir"
        end
      end
    end
  end
end