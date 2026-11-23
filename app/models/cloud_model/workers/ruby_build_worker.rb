module CloudModel
  module Workers
    # Builds one {CloudModel::RubyRelease} on the build host: a throwaway
    # ZFS clone of a finished core template of the os/arch (the libraries
    # the guests run against) gets the build dependencies, the release
    # tarball from cache.ruby-lang.org checked against the SHA256 of the
    # release index, and a plain `--prefix=/opt/ruby/ruby-<version>`
    # build (`--enable-shared --enable-load-relative`: the interpreter and
    # its library find each other relative to the binary, nothing refers to
    # the chroot). The installed tree is copied into the host's per-(os,
    # arch) dataset, where the guests mount it read-only; the clone is
    # destroyed. No version manager, no keyserver, no `curl | bash`.
    class RubyBuildWorker < BaseWorker
      attr_reader :release

      BUILD_PACKAGES = %w(build-essential curl ca-certificates xz-utils bison libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev libgdbm-dev libgmp-dev).freeze

      # @param host [CloudModel::Host] the build host for the release's arch
      # @param release [CloudModel::RubyRelease]
      # @param index [Hash, nil] the release index ({RubyRelease.index}),
      #   fetched when not given
      def initialize host, release:, index: nil
        super host
        @release = release
        @index = index
      end

      # The release index entry: tarball url and sha256.
      def source
        @source ||= begin
          entry = (@index || CloudModel::RubyRelease.index)[release.version]
          raise "Ruby #{release.version} is not in the release index #{CloudModel::RubyRelease::INDEX_URL}" unless entry
          entry
        end
      end

      # A finished core template of the os/arch, else a finished guest
      # template: the libraries the release links against.
      def base_template
        @base_template ||= CloudModel::GuestCoreTemplate.where(os_version: release.os_version, arch: release.arch, build_state_id: 0xf0).order(created_at: :desc).first ||
          CloudModel::GuestTemplate.where(os_version: release.os_version, arch: release.arch, build_state_id: 0xf0).order(created_at: :desc).first ||
          raise("no finished core or guest template for #{release.os_version} #{release.arch} on which to build #{release.name}")
      end

      # The throwaway clone the release is compiled in.
      def buildenv
        @buildenv ||= CloudModel::BuildZfsVolume.new @host, "#{CloudModel.config.build_dataset}/ruby-build/#{release.name}-#{release.os_version}-#{release.arch}",
          mountpoint: "/cloud/build/ruby-build/#{release.name}-#{release.os_version}-#{release.arch}"
      end

      # @return [CloudModel::RubyRelease] the built release, present on the host
      def build!
        template = base_template
        template.ensure_build_volume! @host if template.respond_to?(:ensure_build_volume!)
        release.ensure_dataset_on! @host
        buildenv.prepare_from! template.build_dataset
        @host.exec! "cp /etc/resolv.conf #{buildenv.rootfs_path.shellescape}/etc/resolv.conf", 'Failed to copy resolv.conf into the build system'
        chroot! buildenv.rootfs_path, build_script, "building #{release.name} failed on #{@host.name}"
        @host.exec! "rm -rf #{release.dir.shellescape} && cp -a #{"#{buildenv.rootfs_path}#{release.guest_dir}".shellescape} #{release.dir.shellescape}",
          "copying #{release.name} into #{release.mountpoint} failed on #{@host.name}"
        @host.exec! "test -x #{release.dir.shellescape}/bin/ruby", "#{release.name} is not in #{release.mountpoint} after the copy"
        release
      ensure
        cleanup_chroot_quietly buildenv.rootfs_path
        buildenv.destroy!
      end

      def build_script
        [
          'set -e',
          'export DEBIAN_FRONTEND=noninteractive',
          'apt-get update -q',
          "apt-get install -y -q --no-install-recommends #{BUILD_PACKAGES * ' '}",
          'mkdir -p /usr/src/ruby && cd /usr/src/ruby',
          "curl -fsSL -o ruby.tar.xz #{source[:url].shellescape}",
          "echo #{"#{source[:sha256]}  ruby.tar.xz".shellescape} | sha256sum -c -",
          'tar -xJf ruby.tar.xz',
          "cd #{release.name}",
          "./configure --prefix=#{release.guest_dir} --enable-shared --enable-load-relative --disable-install-doc --disable-install-rdoc",
          'make -j"$(nproc)"',
          'make install',
          # the result runs, finds its library and the extensions the apps need
          "#{release.guest_dir}/bin/ruby -ropenssl -ryaml -rzlib -rreadline -e 'print RUBY_VERSION' | grep -qx #{release.version.shellescape}",
          "#{release.guest_dir}/bin/gem --version >/dev/null",
          "#{release.guest_dir}/bin/bundle --version >/dev/null"
        ].join("\n")
      end
    end
  end
end
