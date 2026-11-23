module CloudModel
  module Workers
    module Mixins
      # The Ruby layout inside a rootfs — a guest being deployed, a template
      # or a build system under construction: the Rubies come read-only from
      # the host's per-(os, arch) dataset ({CloudModel::RubyRelease}) at
      # `/opt/ruby`, and the rootfs gets
      #
      # * `/usr/local/ruby/bin/<program>` — one shim per program found in
      #   the releases' bin directories, which picks the release for the
      #   working directory and a writable gem home per line
      #   (`support/ruby/shim.sh`);
      # * `/usr/local/ruby/current -> /opt/ruby/ruby-<default>` — the
      #   default release as one fixed path, and `/etc/ruby-version` with
      #   the default line the shims fall back to;
      # * `/etc/profile.d/ruby.sh` — the shims on the PATH of login shells
      #   (and of the chroot wrapper, which sources /etc/profile);
      # * `/var/lib/gems/<abi>` — the gem home per line, group www when the
      #   rootfs knows that group.
      #
      # Build chroots get the dataset bind-mounted at `/opt/ruby`
      # ({#bind_ruby_dataset}); a guest gets it as a read-only disk device
      # (GuestWorker#ensure_ruby).
      module RubyLayout
        SHIM_DIR = '/usr/local/ruby/bin'.freeze
        SHIM = "#{SHIM_DIR}/.shim".freeze
        CURRENT = '/usr/local/ruby/current'.freeze
        GUEST_MOUNT = '/opt/ruby'.freeze
        GEM_HOME_ROOT = '/var/lib/gems'.freeze

        # Writes the layout into `rootfs` on @host for the releases the host
        # carries for (os, arch).
        # @param default_line [String] the line of `/usr/local/ruby/current`
        #   and `/etc/ruby-version`, e.g. "3.4" (a full version pins)
        # @param lines [Array<String>] every line the rootfs needs a gem home for
        # @return [String] the default release's version
        def write_ruby_layout rootfs, os_version:, arch:, default_line:, lines: [default_line]
          versions = CloudModel::RubyRelease.versions_on @host, os_version, arch
          default = CloudModel::RubyRelease.resolve default_line, versions
          raise "no Ruby release of line #{default_line} for #{os_version} #{arch} on #{@host.name} (has: #{versions.join(' ').presence || 'none'})" unless default
          missing = lines.map { |l| CloudModel::RubyRelease.line_of l }.uniq.reject { |l| CloudModel::RubyRelease.newest l, versions }
          raise "no Ruby release of line #{missing.join(', ')} for #{os_version} #{arch} on #{@host.name}" if missing.any?

          mountpoint = CloudModel::RubyRelease.mountpoint os_version, arch
          mkdir_p "#{rootfs}#{GUEST_MOUNT}"
          mkdir_p "#{rootfs}#{SHIM_DIR}"
          render_to_remote '/cloud_model/support/ruby/shim.sh', "#{rootfs}#{SHIM}", 0755
          programs = ruby_programs_on mountpoint
          @host.exec! "cd #{"#{rootfs}#{SHIM_DIR}".shellescape} && for p in #{programs.map(&:shellescape) * ' '}; do ln -sfn .shim \"$p\"; done",
            'Failed to write the ruby shims'
          @host.exec! "ln -sfn #{"#{GUEST_MOUNT}/ruby-#{default}".shellescape} #{"#{rootfs}#{CURRENT}".shellescape}", 'Failed to point /usr/local/ruby/current'
          @host.exec! "printf '%s\\n' #{default_line.to_s.shellescape} > #{"#{rootfs}/etc/ruby-version".shellescape}", 'Failed to write /etc/ruby-version'
          mkdir_p "#{rootfs}/etc/profile.d"
          render_to_remote '/cloud_model/support/ruby/profile_ruby.sh', "#{rootfs}/etc/profile.d/ruby.sh", 0644
          # RVM's hook must not shadow the shims on a rootfs that still has it
          @host.exec "test -f #{"#{rootfs}/etc/profile.d/rvm.sh".shellescape} && mv -f #{"#{rootfs}/etc/profile.d/rvm.sh".shellescape} #{"#{rootfs}/etc/profile.d/rvm.sh.disabled".shellescape}"
          lines.map { |l| CloudModel::RubyRelease.abi_of l }.uniq.each do |abi|
            ensure_gem_home rootfs, abi
          end
          default
        end

        # The gem home of a line: writable for group www when the rootfs has
        # that group (the shims fall back to $HOME/.gem for anyone else).
        def ensure_gem_home rootfs, abi
          dir = "#{rootfs}#{GEM_HOME_ROOT}/#{abi}"
          mkdir_p dir
          gid = www_gid_in rootfs
          @host.exec! "chown 0:#{gid || 0} #{dir.shellescape} && chmod 2775 #{dir.shellescape}", "Failed to set up the gem home #{dir}"
        end

        # The group id of www in the rootfs's /etc/group, nil when there is none.
        def www_gid_in rootfs
          success, out = @host.exec "awk -F: '$1 == \"www\" { print $3 }' #{"#{rootfs}/etc/group".shellescape}"
          gid = out.to_s.strip
          success && gid =~ /\A\d+\z/ ? gid.to_i : nil
        end

        # Every program name in the bin directories of the releases on the host.
        def ruby_programs_on mountpoint
          success, out = @host.exec "ls -1 #{mountpoint.shellescape}/ruby-*/bin/ 2>/dev/null"
          names = out.to_s.split("\n").map(&:strip).reject { |n| n.empty? || n.end_with?(':') }.uniq.sort
          raise "no Ruby programs under #{mountpoint} on #{@host.name}" unless success && names.any?
          names
        end

        # Bind-mounts the host's dataset read-only at <rootfs>/opt/ruby for a
        # chroot build (idempotent). cleanup_chroot unmounts it with the
        # other submounts; {#unbind_ruby_dataset} does it explicitly.
        def bind_ruby_dataset rootfs, os_version:, arch:
          mountpoint = CloudModel::RubyRelease.mountpoint os_version, arch
          target = "#{rootfs}#{GUEST_MOUNT}"
          mkdir_p target
          return if @host.mounted_at? target
          @host.exec! "mount --bind -o ro #{mountpoint.shellescape} #{target.shellescape}", "Failed to bind the ruby dataset into #{rootfs}"
        end

        def unbind_ruby_dataset rootfs
          target = "#{rootfs}#{GUEST_MOUNT}"
          return unless @host.mounted_at? target
          @host.exec! "umount #{target.shellescape}", "Failed to unmount the ruby dataset from #{rootfs}"
        end
      end
    end
  end
end
