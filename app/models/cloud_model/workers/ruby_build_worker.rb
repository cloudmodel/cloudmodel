module CloudModel
  module Workers
    # Compiles a Ruby release with RVM on the build host, inside a throwaway
    # clone of a finished guest template (the same libraries the guests run
    # against), and packs the result as an archive the {RubyPatch} unpacks
    # into the running guests. The clone is destroyed afterwards; the archive
    # stays in /tmp on the build host until the patch pulled it.
    class RubyBuildWorker < BaseWorker
      attr_reader :template, :version

      # @param host [CloudModel::Host] the build host for the template's arch
      # @param template [CloudModel::GuestTemplate] a finished template of the
      #   target os/arch whose components include a ruby (RVM and the build
      #   dependencies are in it)
      # @param version [String] full release, e.g. "3.4.13"
      # @param rvm_update [Boolean] `rvm get master` before the install
      def initialize host, template:, version:, rvm_update: false
        super host
        @template = template
        @version = version
        @rvm_update = rvm_update
      end

      def ruby_name
        "ruby-#{version}"
      end

      def volume
        @volume ||= CloudModel::BuildZfsVolume.new @host,
          "#{CloudModel.config.build_dataset}/ruby/#{version}/#{template.id}",
          mountpoint: "/cloud/build/ruby/#{version}/#{template.id}"
      end

      # @param archive [String] path on the build host the gzipped tar is written to
      # @return [String] the archive path
      def build! archive
        template.ensure_build_volume! @host
        volume.prepare_from! template.build_dataset
        @host.exec! "cp /etc/resolv.conf #{volume.rootfs_path.shellescape}/etc/resolv.conf", "Failed to copy resolv.conf into the build system"
        chroot! volume.rootfs_path, build_script, "rvm install #{ruby_name} failed on #{@host.name}"
        pack = "cd #{volume.rootfs_path.shellescape}/usr/local/rvm && tar -cf - rubies/#{ruby_name} gems/#{ruby_name}* environments/#{ruby_name}* wrappers/#{ruby_name}* | gzip -1 > #{archive.shellescape}"
        @host.exec! pack, "packing #{ruby_name} on #{@host.name} failed"
        archive
      ensure
        cleanup_chroot_quietly volume.rootfs_path
        volume.destroy!
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
