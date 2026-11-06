module CloudModel
  module Workers
    module Services
      # Worker that configures the Forgejo Actions runner inside a guest container.
      #
      # Generates the shared registration secret on the first deploy, renders
      # the runner config (connection, labels, capacity, job environment) and
      # asks the linked {Services::Forgejo} instance to register the runner
      # right away, so it can pick up jobs as soon as the guest is up. A failed
      # live registration is not fatal: the Forgejo service registers every
      # linked runner again on its own next deploy.
      class ForgejoRunnerWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          comment_sub_step "Config forgejo runner"

          if @model.registration_secret.blank?
            @model.registration_secret = SecureRandom.hex(20)
            @model.save
          end

          if @model.effective_instance_url.blank?
            raise "Forgejo runner needs an instance to connect to (link a Forgejo service or set the instance URL)"
          end

          render_to_guest "/cloud_model/guest/etc/forgejo_runner/config.yml", "/etc/forgejo-runner/config.yml", 0640, guest: @guest, model: @model
          # The config carries the registration token; the daemon runs as forgejo-runner.
          chroot! @guest.deploy_path, "chown root:forgejo-runner /etc/forgejo-runner/config.yml && chmod 640 /etc/forgejo-runner/config.yml", "Failed to set runner config ownership"

          write_ssh_identity

          register_with_instance
        end

        # SSH identity of the runner user: jobs clone git-source gems (and
        # anything else over SSH) with the runner's own key, which the admin
        # registers on a read-only account of the instance. The instance's
        # host key is accepted on first contact, no interactive prompt in jobs.
        def write_ssh_identity
          @model.ensure_ssh_key!
          comment_sub_step "Install runner SSH identity (#{@model.ssh_public_key.to_s.split(' ').first(2).join(' ')[0, 40]}…)"

          ssh_dir = "/var/lib/forgejo-runner/.ssh"
          mkdir_p "#{@guest.deploy_path}#{ssh_dir}"
          upload_to_guest @model.ssh_private_key, "#{ssh_dir}/id_ed25519", "0600"
          upload_to_guest "#{@model.ssh_public_key}\n", "#{ssh_dir}/id_ed25519.pub", "0644"
          # The runner's one identity for every git host a job may reach
          # (the instance, and the hosts of git-source gems and cargo
          # dependencies); host keys are accepted on first contact.
          config = "Host *\n  IdentitiesOnly yes\n  IdentityFile ~/.ssh/id_ed25519\n  StrictHostKeyChecking accept-new\n"
          upload_to_guest config, "#{ssh_dir}/config", "0600"
          chroot! @guest.deploy_path, "chown -R forgejo-runner:forgejo-runner #{ssh_dir} && chmod 700 #{ssh_dir}", "Failed to set runner .ssh ownership"
        end

        # Live registration on the linked instance (no-op without one).
        def register_with_instance
          forgejo = @model.forgejo_service
          return unless forgejo

          comment_sub_step "Register runner with Forgejo service '#{forgejo.name}'"
          begin
            forgejo.register_actions_runner! @model
          rescue Exception => e
            comment_sub_step "Live registration failed (#{e.message.lines.first.to_s.strip}); the Forgejo service registers the runner on its next deploy"
          end
        end

        def auto_restart
          true
        end

        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/forgejo_runner.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"
          super
        end
      end
    end
  end
end
