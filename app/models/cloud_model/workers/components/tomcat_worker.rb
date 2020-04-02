module CloudModel
  module Workers
    module Components
      class TomcatWorker < BaseWorker
        def build build_path
          chroot! build_path, "apt-get install tomcat8 tomcat8-admin -y", "Failed to install tomcat"
          # Fix Ubuntu bug
          # https://bugs.launchpad.net/ubuntu/+source/ca-certificates-java/+bug/1396760
          chroot! build_path, "/var/lib/dpkg/info/ca-certificates-java.postinst configure", "Failed to config CA certs for tomcat"
     
          render_to_remote "/cloud_model/guest/bin/tomcat8", "#{build_path}/usr/sbin/tomcat8", 0755
          render_to_remote "/cloud_model/guest/etc/systemd/system/tomcat8.service", "#{build_path}/etc/systemd/system/tomcat8.service"     
        end
      end
    end
  end
end