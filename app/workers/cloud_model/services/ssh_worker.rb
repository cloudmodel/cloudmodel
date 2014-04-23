module CloudModel
  module Services
    class SshWorker < BaseWorker
      def write_config
        Rails.logger.debug "    Write SSH config"
        @host.ssh_connection.sftp.file.open(File.expand_path("etc/ssh/sshd_config", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/ssh/sshd_config", guest: @guest, model: @model)
        end
      
        # Copy or Generate sshd key
        ssh_host_key_target = File.expand_path("etc/", @guest.deploy_path)
        ssh_host_key_source = "/inst/hosts_by_ip/#{@guest.private_address}/etc/ssh"
      
      
        FileUtils.mkdir_p ssh_host_key_source
        %w(dsa ecdsa rsa).each do |type|
          key_file = "#{ssh_host_key_source}/ssh_host_#{type}_key"
          unless File.exists?(key_file)
            `ssh-keygen -t #{type} -f "#{key_file}" -N ''`
          end
        end
      
        FileUtils.cp_r "#{ssh_host_key_source}", ssh_host_key_target
      
        # Copy over client ssh files
        ssh_target = File.expand_path("var/www/.ssh", @guest.deploy_path)
        FileUtils.rm_r ssh_target
        FileUtils.cp_r '/inst/ssh/client_keys', ssh_target
        FileUtils.chown_R 'www', 'www', ssh_target
      end
    
      def auto_start
        Rails.logger.debug "    Add SSH to runlevel default"
        `ln -sf /etc/init.d/sshd #{@guest.deploy_path}/etc/runlevels/default/`
      end
    end
  end
end