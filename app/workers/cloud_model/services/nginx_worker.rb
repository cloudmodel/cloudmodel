require 'stringio'
require 'securerandom'

module CloudModel
  module Services
    class NginxWorker < CloudModel::Services::BaseWorker
      def write_config
        puts "        Install nginx"
        chroot! @guest.deploy_path, "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7", "Failed to add fusion key"
        chroot! @guest.deploy_path, "apt-get install apt-transport-https ca-certificates -y", "Failed to install ca-certificates"
        render_to_remote "/cloud_model/guest/etc/apt/sources.list.d/passenger.list", "#{@guest.deploy_path}/etc/apt/sources.list.d/passenger.list", 600
        chroot! @guest.deploy_path, "apt-get update", "Failed to update packages"
        chroot! @guest.deploy_path, "apt-get install nginx-extras passenger -y", "Failed to install nginx+passenger"
      
        puts "        Install ruby deps"
        packages = %w(git bundler)
        packages += %w(zlib1g-dev libxml2-dev) # Nokogiri
        packages << 'ruby-bcrypt' # bcrypt      
        packages << 'nodejs' # JS interpreter 
        packages << 'imagemagick' # imagemagick
        packages << 'libxml2-utils' # xmllint (TODO: needed for one rails project, make this configurable)
        chroot! @guest.deploy_path, "apt-get install #{packages * ' '} -y", "Failed to install packeges for deployment of rails app"
         
        puts "        Config nginx"
                
        render_to_remote "/cloud_model/guest/etc/nginx/nginx.conf", "#{@guest.deploy_path}/etc/nginx/nginx.conf", guest: @guest, model: @model      
        render_to_remote "/cloud_model/guest/etc/default/rails", "#{@guest.deploy_path}/etc/default/rails", guest: @guest, model: @model
        chroot! @guest.deploy_path, "groupadd -f -r -g 1001 www && useradd -c 'added by cloud_model for nginx' -d /var/www -s /bin/bash -r -g 1001 -u 1001 www", "Failed to add www user"
        
      
        puts "        Make nginx root"
        mkdir_p "#{@guest.deploy_path}#{@model.www_root}"
      
        if @model.ssl_supported?
          puts "        Write SSL files"
          ssl_base_dir = File.expand_path("etc/nginx/ssl", @guest.deploy_path)
          mkdir_p ssl_base_dir
                  
          @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.crt", ssl_base_dir), 'w') do |f|
            f.write @model.ssl_cert.crt
          end
        
          @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.key", ssl_base_dir), 'w') do |f|
            f.write @model.ssl_cert.key
          end
        
          @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.ca.crt", ssl_base_dir), 'w') do |f|
            f.write @model.ssl_cert.ca
          end
        end
       
        if @model.deploy_web_image
          mkdir_p "#{@guest.deploy_path}#{@model.www_root}/current"
        
          puts "        Deploy WebImage #{@model.deploy_web_image.name} to #{@guest.deploy_path}#{@model.www_root}"
          temp_file_name = "/tmp/temp-#{SecureRandom.uuid}.tar"
          io = StringIO.new(@model.deploy_web_image.file.data)
          @host.sftp.upload!(io, temp_file_name)
          @host.exec "cd #{@guest.deploy_path}#{@model.www_root} && tar xpf #{temp_file_name}"
          @host.sftp.remove!(temp_file_name)
          
          if @model.deploy_web_image.has_mongodb?
            render_to_remote "/cloud_model/web_image/mongoid.yml", "#{@guest.deploy_path}#{@model.www_root}/current/config/mongoid.yml", guest: @guest, model: @model
          end
        
          if @model.deploy_web_image.has_redis?
            render_to_remote "/cloud_model/web_image/redis.yml", "#{@guest.deploy_path}#{@model.www_root}/current/config/redis.yml", guest: @guest, model: @model
          end
        end
      
        @host.exec "chmod -R 2775 #{@guest.deploy_path}#{@model.www_root}"
        chroot @guest.deploy_path, "chown -R www:www #{@model.www_root}"
        
        log_dir_path = "/var/log/nginx/"
        mkdir_p log_dir_path
        @host.exec  "chmod -R 2770 #{@guest.deploy_path}#{log_dir_path}"
        chroot @guest.deploy_path, "chown -R www:www #{log_dir_path}"
      end
    
      def auto_restart
        true
      end
      
      def auto_start
        super
        render_to_remote "/cloud_model/guest/etc/systemd/system/nginx.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"
        # TODO: Resolve dependencies
        # Services::Ssh.new(@host, @options).write_config
      end
    end
  end
end