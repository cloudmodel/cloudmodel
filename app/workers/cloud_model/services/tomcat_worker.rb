require 'stringio'
require 'securerandom'

module CloudModel
  module Services
    class TomcatWorker < CloudModel::Services::BaseWorker
      def write_config
        target = "#{@guest.deploy_path}/var/tomcat" 
        
        puts "        Install tomcat"
        chroot! @guest.deploy_path, "apt-get install openjdk-8-jre-headless tomcat8 tomcat8-admin -y", "Failed to install tomcat"
        # Fix Ubuntu bug
        # https://bugs.launchpad.net/ubuntu/+source/ca-certificates-java/+bug/1396760
        chroot! @guest.deploy_path, "/var/lib/dpkg/info/ca-certificates-java.postinst configure", "Failed to config CA certs for tomcat"

        
        puts "        Deploy WAR Image #{@model.deploy_war_image.name} to #{@guest.deploy_path}#{target}"
        temp_file_name = "/tmp/temp-#{SecureRandom.uuid}.tar"
        io = StringIO.new(@model.deploy_war_image.file.data)
        @host.sftp.upload!(io, temp_file_name)     
        mkdir_p target
        @host.exec "cd #{target.shellescape} && tar xjpf #{temp_file_name}"
        @host.sftp.remove!(temp_file_name)
        
        # Read manifest
        manifest = ''
        @host.sftp.file.open( "#{target}/manifest.yml") do |f|
          manifest = YAML.load(f.read)
        end
        
        puts "        Write tomcat config"
        tomcat_conf_dir = '/etc/tomcat8'
        #tomcat_conf_dir = '/usr/share/tomcat8/conf'
        
        mkdir_p "#{@guest.deploy_path}#{tomcat_conf_dir}/Catalina/localhost"
        
        render_to_remote "/cloud_model/guest/etc/default/tomcat8", "#{@guest.deploy_path}/etc/default/tomcat8", manifest: manifest, worker: self, guest: @guest, model: @model      
        render_to_remote "/cloud_model/guest/etc/tmpfiles.d/tomcat8.conf", "#{@guest.deploy_path}/etc/tmpfiles.d/tomcat8.conf"
        render_to_remote "/cloud_model/guest/etc/tomcat8/server.xml", "#{@guest.deploy_path}#{tomcat_conf_dir}/server.xml", 0640, guest: @guest, model: @model      
        render_to_remote "/cloud_model/guest/etc/tomcat8/servlet.xml", "#{@guest.deploy_path}#{tomcat_conf_dir}/Catalina/localhost/ROOT.xml", 0640, manifest: manifest, worker: self, guest: @guest, model: @model    
        render_to_remote "/cloud_model/guest/etc/tomcat8/tomcat-users.xml", "#{@guest.deploy_path}#{tomcat_conf_dir}/tomcat-users.xml", 0640, guest: @guest, model: @model      
        chroot! @guest.deploy_path, "rm -rf /var/lib/tomcat8/webapps/ROOT", "Failed to remove genuine root app for tomcat"
        
        
        chroot @guest.deploy_path, "chown -R tomcat8:tomcat8 /var/tomcat #{tomcat_conf_dir}"
      end
    
      def interpolate_value(value)
        value.to_s.gsub("%TARGET%", "/var/tomcat").gsub("%DATA_DIR%", "/var/tomcat/data")
      end
    
      def auto_start
        puts "        Add Tomcat to runlevel default"
        render_to_remote "/cloud_model/guest/bin/tomcat8", "#{@guest.deploy_path}/usr/sbin/tomcat8", 0755
        render_to_remote "/cloud_model/guest/etc/systemd/system/tomcat8.service", "#{@guest.deploy_path}/etc/systemd/system/tomcat8.service"
        
        @host.exec "ln -sf /etc/systemd/system/tomcat8.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
      end
    end
  end
end