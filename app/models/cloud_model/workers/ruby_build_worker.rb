module CloudModel
  module Workers
    # Compiles a Ruby release with RVM on the build host, inside a throwaway
    # clone of a finished guest template (the same libraries the guests run
    # against), and commits the result as a small ZFS volume — the RVM
    # directories of that one Ruby — that {RubyPatch} syncs host to host like
    # a template and unpacks into the running guests. The clone is destroyed
    # afterwards.
    class RubyBuildWorker < BaseWorker
      attr_reader :template, :version, :volume

      # @param host [CloudModel::Host] the build host for the template's arch
      # @param template [CloudModel::GuestTemplate] a finished template of the
      #   target os/arch whose components include a ruby (RVM and the build
      #   dependencies are in it)
      # @param version [String] full release, e.g. "3.4.13"
      # @param volume [CloudModel::BuildZfsVolume] the ruby volume to commit on `host`
      # @param rvm_update [Boolean] `rvm get master` before the install
      def initialize host, template:, version:, volume:, rvm_update: false
        super host
        @template = template
        @version = version
        @volume = volume
        @rvm_update = rvm_update
      end

      def ruby_name
        "ruby-#{version}"
      end

      # The template clone the Ruby is compiled in, next to the ruby volume.
      def buildenv
        @buildenv ||= CloudModel::BuildZfsVolume.new @host, "#{volume.dataset_name}-buildenv", mountpoint: "#{volume.mountpoint}-buildenv"
      end

      # @return [CloudModel::BuildZfsVolume] the committed ruby volume
      def build!
        template.ensure_build_volume! @host
        buildenv.prepare_from! template.build_dataset
        @host.exec! "cp /etc/resolv.conf #{buildenv.rootfs_path.shellescape}/etc/resolv.conf", "Failed to copy resolv.conf into the build system"
        chroot! buildenv.rootfs_path, build_script, "rvm install #{ruby_name} failed on #{@host.name}"
        volume.prepare!
        @host.exec! "cd #{buildenv.rootfs_path.shellescape}/usr/local/rvm && cp -a --parents rubies/#{ruby_name} gems/#{ruby_name}* environments/#{ruby_name}* wrappers/#{ruby_name}* #{volume.mountpoint.shellescape}/",
          "copying #{ruby_name} into the ruby volume failed on #{@host.name}"
        volume.commit!
        volume
      ensure
        cleanup_chroot_quietly buildenv.rootfs_path
        buildenv.destroy!
      end

      def build_script
        [
          "set -e",
          ("/usr/local/rvm/bin/rvm get master" if @rvm_update),
          "/usr/local/rvm/bin/rvm install #{ruby_name} --disable-binary --autolibs=read-fail",
          "test -x /usr/local/rvm/rubies/#{ruby_name}/bin/ruby",
          # stop the gpg helpers rvm may have started so the chroot unmounts cleanly
          "gpgconf --kill all >/dev/null 2>&1 || true"
        ].compact.join("\n")
      end
    end
  end
end
