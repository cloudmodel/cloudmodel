module CloudModel
  module Workers
    module Services
      # Abstract base class for all service workers.
      #
      # Service workers are instantiated with a running {CloudModel::LxdContainer}
      # and the corresponding service model. They handle writing configuration
      # files into the container's rootfs and registering the service with systemd.
      #
      # Subclasses implement {#write_config} to render templates, and may override
      # {#auto_restart} and {#auto_start} to control systemd unit behaviour.
      class BaseWorker  < CloudModel::Workers::BaseWorker

        # @param lxc [CloudModel::LxdContainer] the container being configured
        # @param model [CloudModel::Services::Base] the service model instance
        def initialize lxc, model
          @lxc = lxc
          @guest = @lxc.guest
          @host = @guest.host
          @model = model
        end

        # @return [CloudModel::Guest] the guest that owns the service
        def guest
          @guest
        end

        # @return [CloudModel::Host] the host running the guest
        def host
          @host
        end

        # Directories and rendered files in the offline rootfs are root-owned
        # as written (unshifted clone, see Workers::BaseWorker#own_in_rootfs);
        # the old host-range chown is neither needed nor correct there.

        # Uploads raw content string into the running LXD container via `lxc file push`.
        # @param content [String] file content to write
        # @param remote_file [String] absolute path inside the container
        # @param perm [String] octal permission string (default: `"0600"`)
        # @return [true]
        def upload_to_guest content, remote_file, perm = "0600"
          tmp_file = "/tmp/cloudmodel_#{BSON::ObjectId.new}"

          @host.sftp.file.open(tmp_file, 'w', 0600) do |f|
            f.puts content
          end

          host.exec!("lxc file push #{tmp_file.shellescape} #{@lxc.name}/#{remote_file.shellescape} -p --mode #{perm}", "Failed to upload #{remote_file}")
          host.exec("rm #{tmp_file.shellescape}")

          # For a stopped container LXD mounts the volume for the push and
          # unmounts it afterwards (unless chroot submounts of an earlier step
          # happen to keep it busy), switching it to mountpoint=legacy on the
          # way. Everything this worker then writes straight into the rootfs
          # (render_to_remote, chroot) must land in the volume, not on the
          # bare mountpoint directory — so remount. A no-op while it runs.
          @lxc.mount
          true
        end

        # Renders a template and pushes the result into the running container.
        # @param template [String] view template path
        # @param remote_file [String] absolute path inside the container
        def render_to_guest template, remote_file, *param_array
          perm = if false and param_array.first.is_a? Integer
            param_array.shift
          else
            "0600"
          end

          locals = param_array.pop || {}

          content = render(template, locals)

          upload_to_guest content, remote_file, perm
        end

        # Writes all configuration files for this service into the container rootfs.
        # Override in subclasses to render templates and run chroot commands.
        def write_config
        end

        # Shell one-liner that creates the `www` user and group (uid/gid 1001)
        # inside the guest if they are missing, and is a no-op otherwise.
        WWW_USER_COMMAND = "groupadd -f -r -g 1001 www && id -u www || useradd -c 'added by cloud_model for nginx' -d /var/www -s /bin/bash -r -g 1001 -u 1001 www".freeze

        # Ensures the `www` user (uid 1001) exists in the guest rootfs.
        #
        # Idempotent, so every worker that writes files owned by `www` can
        # call it, regardless of the order in which the guest's services are
        # configured: a guest with its SSH service listed before Nginx would
        # otherwise `chown www:www` into a rootfs that has no such user yet.
        def ensure_www_user!
          chroot! @guest.deploy_path, WWW_USER_COMMAND, "Failed to add www user"
        end

        # @return [String] systemd service unit name (defaults to the model class element name)
        def service_name
          @model.class.model_name.element.shellescape
        end

        # @return [String] path to the systemd drop-in override directory for this service
        def overlay_path
          "#{@guest.deploy_path.shellescape}/etc/systemd/system/#{service_name}.service.d"
        end

        # @return [Boolean] whether a systemd `Restart=always` drop-in is written (default: `false`)
        def auto_restart
          false
        end

        # Enables the service in the systemd `multi-user.target` and optionally
        # writes a restart drop-in if {#auto_restart} returns `true`.
        def auto_start
          comment_sub_step "Add #{@model.class.model_name.human} to runlevel default"
          @host.exec "ln -sf /lib/systemd/system/#{service_name}.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
          if auto_restart
            mkdir_p overlay_path
            render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{overlay_path}/restart.conf", 644
          end
        end

      end
    end
  end
end