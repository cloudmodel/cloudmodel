module CloudModel
  module Services
    class SshWorker < CloudModel::Services::BaseWorker
      def write_config
        puts "        Install SSH"
        #chroot! @guest.deploy_path, "apt-get install ssh -y", "Failed to install SSH"
        chroot! @guest.deploy_path, "apt-get install busybox dropbear -y", "Failed to install BusyBox"
        
        mkdir_p "#{@guest.deploy_path}/etc/ssh"
        puts "        Write SSH config"
        render_to_remote "/cloud_model/guest/etc/default/dropbear", "#{@guest.deploy_path}/etc/default/dropbear", 0600, service: @model
        
        # @host.sftp.file.open(File.expand_path("etc/ssh/sshd_config", @guest.deploy_path), 'w') do |f|
        #   f.write render("/cloud_model/guest/etc/ssh/sshd_config", guest: @guest, model: @model)
        # end
      
        # Copy or Generate sshd key
        ssh_host_key_target = File.expand_path("etc/", @guest.deploy_path)
        ssh_host_key_source = "/inst/hosts_by_ip/#{@guest.private_address}/etc/dropbear"
          
        mkdir_p ssh_host_key_source
        %w(dss ecdsa rsa).each do |type|
          key_file = "#{ssh_host_key_source}/dropbear_#{type}_host_key"
          begin
            @host.sftp.lstat! key_file
          rescue Net::SFTP::StatusException => e
            #@host.exec! "ssh-keygen -t #{type} -f #{key_file.shellescape} -N ''", 'Failed to generate host keys'
            @host.exec! "#{@guest.deploy_path}/usr/bin/dropbearkey -t #{type} -f #{key_file.shellescape}", "Failed to generate #{type} host keys"
          end
        end
      
        @host.exec! "cp -ra #{ssh_host_key_source.shellescape} #{ssh_host_key_target.shellescape}", "Failed to copy host keys"        
      
        # Copy over client ssh files
        ssh_target = File.expand_path("var/www/.ssh", @guest.deploy_path)
        @host.exec "rm -rf #{ssh_target.shellescape}"
        mkdir_p ssh_target
        @host.sftp.file.open("#{ssh_target}/authorized_keys", 'w') do |f|
          f.write CloudModel::SshPubKey.all.to_a * "\n"
        end
      end
    
      def service_name
        "dropbear"
      end
      
      def auto_restart
        true
      end
    end
  end
end