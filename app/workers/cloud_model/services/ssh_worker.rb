module CloudModel
  module Services
    class SshWorker < CloudModel::Services::BaseWorker
      def write_config
        puts "        Install SSH"
        chroot! @guest.deploy_path, "apt-get install ssh -y", "Failed to install SSH"
        
        puts "        Write SSH config"
        @host.sftp.file.open(File.expand_path("etc/ssh/sshd_config", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/ssh/sshd_config", guest: @guest, model: @model)
        end
      
        # Copy or Generate sshd key
        ssh_host_key_target = File.expand_path("etc/", @guest.deploy_path)
        host_source_dir = "/inst/hosts_by_ip/#{@guest.private_address}"
        ssh_host_key_source = "#{host_source_dir}/etc/ssh"
        ssh_www_key_source = "#{host_source_dir}/var/www/.ssh"
            
        mkdir_p ssh_host_key_source
        %w(dsa ed25519 rsa).each do |type|
          key_file = "#{ssh_host_key_source}/ssh_host_#{type}_key"
          begin
            @host.sftp.lstat! key_file
          rescue Net::SFTP::StatusException => e
            @host.exec! "ssh-keygen -t #{type} -f #{key_file.shellescape} -N ''", 'Failed to generate host keys'
          end
        end
      
        @host.exec! "cp -ra #{ssh_host_key_source.shellescape} #{ssh_host_key_target.shellescape}", "Failed to copy host keys"        
      
        # Copy over client ssh files
        ssh_target = File.expand_path("var/www/.ssh", @guest.deploy_path)
        @host.exec "rm -rf #{ssh_target.shellescape}"
        #@host.exec! "cp -ra /inst/ssh/client_keys #{ssh_target}", "Failed to copy www client keys"
        mkdir_p ssh_www_key_source
        mkdir_p ssh_target
        
        # Copy client keys from inst if existing
        @host.exec! "cp -ra #{ssh_www_key_source.shellescape}/id_* #{ssh_target.shellescape}", "Failed to copy client keys"        
        
        # Write authorized keys from database entries
        @host.sftp.file.open("#{ssh_target}/authorized_keys", 'w') do |f|
          f.write CloudModel::SshPubKey.all.to_a * "\n"
        end
  
        # TODO: Reenable after config for ngix done
        # chroot! @guest.deploy_path, "chown -R www:www /var/www/.ssh", "Failed to change owner of www client keys to user www (1001)"
      end
    
      def service_name
        "sshd"
      end
      
      def auto_restart
        true
      end
    end
  end
end