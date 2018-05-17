module CloudModel
  module Components
    class NginxWorker < BaseWorker
      def build build_path
        ### TODO; Test build in nginx
        ### if running: remove /cloud_model/guest/etc/apt/sources.list.d/passenger.list
        ### if not running: fix sources
        chroot! build_path, "apt-get install dirmngr gnupg -y", "Failed to install key management"
        chroot! build_path, "apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 561F9B9CAC40B2F7", "Failed to add fusion key"
        chroot! build_path, "apt-get install apt-transport-https ca-certificates -y", "Failed to install ca-certificates"
        render_to_remote "/cloud_model/guest/etc/apt/sources.list.d/passenger.list", "#{build_path}/etc/apt/sources.list.d/passenger.list", 600
        chroot! build_path, "apt-get update", "Failed to update packages"
        chroot! build_path, "apt-get install nginx-extras libnginx-mod-http-passenger -y", "Failed to install nginx+passenger"
        log_dir_path = "/var/log/nginx"
        @host.exec! "rm -rf #{build_path}#{log_dir_path}", "Failed to clear log dir"
      end
    end
  end
end