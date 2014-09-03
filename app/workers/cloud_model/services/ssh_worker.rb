module CloudModel
  module Services
    class SshWorker < CloudModel::Services::BaseWorker
      def write_config
        puts "        Write SSH config"
        @host.ssh_connection.sftp.file.open(File.expand_path("etc/ssh/sshd_config", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/ssh/sshd_config", guest: @guest, model: @model)
        end
      
        # Copy or Generate sshd key
        ssh_host_key_target = File.expand_path("etc/", @guest.deploy_path)
        ssh_host_key_source = "/inst/hosts_by_ip/#{@guest.private_address}/etc/ssh"
      
      
        mkdir_p ssh_host_key_source
        %w(dsa ed25519 rsa).each do |type|
          key_file = "#{ssh_host_key_source}/ssh_host_#{type}_key"
          begin
            @host.ssh_connection.sftp.lstat! key_file
          rescue Net::SFTP::StatusException => e
            @host.exec! "ssh-keygen -t #{type} -f #{key_file.shellescape} -N ''", 'Failed to generate host keys'
          end
        end
      
        @host.exec! "cp -ra #{ssh_host_key_source.shellescape} #{ssh_host_key_target.shellescape}", "Failed to copy host keys"        
      
        # Copy over client ssh files
        ssh_target = File.expand_path("var/www/.ssh", @guest.deploy_path)
        @host.exec "rm -rf #{ssh_target.shellescape}"
        #@host.exec! "cp -ra /inst/ssh/client_keys #{ssh_target}", "Failed to copy www client keys"
        mkdir_p ssh_target
        @host.ssh_connection.sftp.file.open("#{ssh_target}/authorized_keys", 'w') do |f|
          f.write CloudModel::SshPubKey.all.to_a * "\n"
        end
  
        @host.exec! "chown -R 1001:1001 #{ssh_target.shellescape}", "Failed to change owner of www client keys to user www (1001)"
      end
    
      def auto_start
        puts "        Add SSH to runlevel default"
        @host.exec "ln -sf /etc/systemd/system/sshd.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
      end
    end
  end
end