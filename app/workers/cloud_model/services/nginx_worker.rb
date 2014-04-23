module CloudModel
  module Services
    class NginxWorker < BaseWorker
      def write_config
        Rails.logger.debug "    Write nginx config"
        @host.ssh_connection.sftp.file.open(File.expand_path("etc/nginx/nginx.conf", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/nginx/nginx.conf", guest: @guest, model: @model)
        end
      
        Rails.logger.debug "    Make nginx root"
        mkdir_p "#{@guest.deploy_path}#{@model.www_root}"
      
        if @model.ssl_supported?
          Rails.logger.debug "    Copy SSL files"
          ssl_base_dir = File.expand_path("etc/nginx/ssl", @guest.deploy_path)
          mkdir_p ssl_base_dir
        
          @host.ssh_connection.sftp.file.open(File.expand_path("#{@guest.external_hostname}.crt", ssl_base_dir), 'w') do |f|
            f.write @model.ssl_cert.crt
          end
        
          @host.ssh_connection.sftp.file.open(File.expand_path("#{@guest.external_hostname}.key", ssl_base_dir), 'w') do |f|
            f.write @model.ssl_cert.key
          end
        
          @host.ssh_connection.sftp.file.open(File.expand_path("#{@guest.external_hostname}.ca.crt", ssl_base_dir), 'w') do |f|
            f.write @model.ssl_cert.ca
          end
        end
       
        if @model.deploy_web_image
          mkdir_p "#{@guest.deploy_path}#{@model.www_root}/current"
        
          Rails.logger.debug "    Deploy WebImage #{@model.deploy_web_image.name} to #{@guest.deploy_path}#{@model.www_root}"
          @host.ssh_connection.sftp.file.open("/tmp/temp.tar", 'wb') do |f|
            f.write @model.deploy_web_image.file_model.data
          end
          @host.exec "cd #{@guest.deploy_path}#{@model.www_root} && tar xpf /tmp/temp.tar"
        
          if @model.deploy_web_image.has_mongodb?
            @host.ssh_connection.sftp.file.open("#{@guest.deploy_path}#{@model.www_root}/current/config/mongoid.yml", 'w') do |f|
              f.write render("/cloud_model/web_image/mongoid.yml", guest: @guest, model: @model)
            end
          end
        
          if @model.deploy_web_image.has_redis?
            @host.ssh_connection.sftp.file.open("#{@guest.deploy_path}#{@model.www_root}/current/config/redis.yml", 'w') do |f|
              f.write render("/cloud_model/web_image/redis.yml", guest: @guest, model: @model)
            end
          end
        end
      
        @host.exec "chmod -R 2775 #{@guest.deploy_path}#{@model.www_root}"
        @host.exec "chown -R www:www #{@guest.deploy_path}#{@model.www_root}"
      end
    
      def auto_start
        Rails.logger.debug "    Add Nginx to runlevel default"
        @host.exec "ln -sf /etc/init.d/sp-nginx #{@guest.deploy_path}/etc/runlevels/default/"
        # TODO: Resolve dependencies
        # Services::Ssh.new(@host, @options).write_config
      end
    end
  end
end