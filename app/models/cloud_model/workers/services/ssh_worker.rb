module CloudModel
  module Workers
    module Services
      # Worker that configures the OpenSSH server inside a guest container.
      #
      # Renders `sshd_config`, ensures host keys exist (generating them if not),
      # persists keys to `/inst/hosts_by_ip/` across redeployments, and copies
      # any client SSH keys for the `www` user.
      class SshWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          comment_sub_step "Write SSH config"
          @host.sftp.file.open(File.expand_path("etc/ssh/sshd_config", @guest.deploy_path), 'w') do |f|
            f.write render("/cloud_model/guest/etc/ssh/sshd_config", guest: @guest, model: @model)
          end

          # Copy or Generate sshd key
          ssh_host_key_target = File.expand_path("etc/", @guest.deploy_path)
          host_source_dir = "/inst/hosts_by_ip/#{@guest.private_address}"
          ssh_host_key_source = "#{host_source_dir}/etc/ssh"
          ssh_www_key_source = "#{host_source_dir}/var/www/.ssh"

          mkdir_p ssh_host_key_source
          %w(dsa ecdsa ed25519 rsa).each do |type|
            key_file = "ssh_host_#{type}_key"
            begin
              @host.sftp.lstat! "#{ssh_host_key_source}/#{key_file}"
            rescue Net::SFTP::StatusException => e
              comment_sub_step "Generate #{type} SSH key"
              chroot! @guest.deploy_path, "ssh-keygen -t #{type} -f /etc/ssh/#{key_file.shellescape} -N ''", 'Failed to generate host keys'
              @host.exec! "cp -ra #{ssh_host_key_target.shellescape}/ssh/#{key_file}* #{ssh_host_key_source.shellescape} ", "Failed to copy new host keys to inst"
            end
          end

          @host.exec! "cp -ra #{ssh_host_key_source.shellescape} #{ssh_host_key_target.shellescape}", "Failed to copy host keys"

          # Copy over client ssh files
          ssh_target = File.expand_path("var/www/.ssh", @guest.deploy_path)
          #@host.exec "rm -rf #{ssh_target.shellescape}"
          #@host.exec! "cp -ra /inst/ssh/client_keys #{ssh_target}", "Failed to copy www client keys"
          mkdir_p ssh_www_key_source
          mkdir_p ssh_target

          # Copy client keys from inst (if existing)
          begin
            if @host.sftp.dir.glob(ssh_www_key_source, 'id_*').size > 0
              @host.exec! "cp -ra #{ssh_www_key_source.shellescape}/id_* #{ssh_target.shellescape}", "Failed to copy client keys"
            end
          rescue Net::SFTP::StatusException => e
          end

          # Host keys stay root-owned (unshifted rootfs: uid 0 IS the container's root).
          # Own the www client keys by name inside the container namespace, not
          # with a raw host-side uid. The tarball-era chroot resolved the
          # container's www (1001) to host 101001, so `chown 101001` worked; a
          # ZFS-volume deploy does not shift the same way, and the raw chown
          # then lands as literal 101001 inside, so sshd StrictModes rejects the
          # keys (not owned by their user). Chowning by name is correct either way.
          chroot! @guest.deploy_path, "chown -R www:www /var/www/.ssh", "Failed to change owner of www client keys to user www"
          chroot! @guest.deploy_path, "chmod 700 /var/www/.ssh", "Failed to set mode on www .ssh dir"
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
end