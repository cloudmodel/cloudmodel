require 'net/http'

module CloudModel
  # One Ruby release for one (os, arch): a directory `ruby-<version>` in the
  # per-host ZFS dataset `<ruby_dataset>/<os>-<arch>` (mounted at
  # `<ruby_mountpoint>/<os>-<arch>`), a plain `--prefix` install built from
  # the tarball on cache.ruby-lang.org on the build host
  # ({Workers::RubyBuildWorker}) and sent host to host as the snapshot
  # `@ruby-<version>` ({Mixins::ZfsDatasetSync}, incremental from the
  # previous release's snapshot). The guests see the dataset read-only at
  # `/opt/ruby`; which release a program runs is decided inside the guest by
  # the shims ({Workers::Mixins::RubyLayout}).
  #
  # No database record: what is built is what the build host's dataset
  # carries, what a guest needs is what its services name
  # ({Guest#ruby_lines_needed}).
  class RubyRelease
    include CloudModel::Mixins::ZfsDatasetSync

    INDEX_URL = 'https://cache.ruby-lang.org/pub/ruby/index.txt'.freeze
    VERSION = /\A\d+\.\d+\.\d+\z/
    LINE = /\A\d+\.\d+\z/

    attr_reader :version, :os_version, :arch

    # @param version [String] full release, e.g. "3.4.13"
    # @param os_version [String] e.g. "debian-12"
    # @param arch [String] e.g. "amd64"
    def initialize version:, os_version:, arch:
      raise ArgumentError, "Ruby release must be a full version like 3.4.13, got #{version.inspect}" unless version.to_s =~ VERSION
      @version = version.to_s
      @os_version = os_version.to_s
      @arch = arch.to_s
    end

    # "3.4" for "3.4.13" (and for "3.4")
    def self.line_of version
      version.to_s.split('.').first(2) * '.'
    end

    # "3.4.0": the gem/ABI directory of a line
    def self.abi_of version
      "#{line_of version}.0"
    end

    def self.dataset os_version, arch
      "#{CloudModel.config.ruby_dataset}/#{os_version}-#{arch}"
    end

    def self.mountpoint os_version, arch
      "#{CloudModel.config.ruby_mountpoint}/#{os_version}-#{arch}"
    end

    # The release directories present on `host` for (os, arch), newest last.
    # @return [Array<String>] versions, e.g. ["3.4.11", "3.4.13"]
    def self.versions_on host, os_version, arch
      success, out = host.exec "ls -1 #{mountpoint(os_version, arch).shellescape} 2>/dev/null"
      return [] unless success
      out.to_s.split("\n").filter_map { |d| d[/\Aruby-(\d+\.\d+\.\d+)\z/, 1] }.sort_by { |v| Gem::Version.new v }
    end

    # The newest of `versions` on `line`, nil when the line has none.
    def self.newest line, versions
      versions.select { |v| line_of(v) == line }.max_by { |v| Gem::Version.new v }
    end

    # Resolves what a guest or service asks for to the release it gets from
    # `versions`: a full version when installed, else the newest of its line.
    def self.resolve wanted, versions
      wanted = wanted.to_s
      return wanted if wanted =~ VERSION && versions.include?(wanted)
      newest line_of(wanted), versions
    end

    # The release index of ruby-lang.org: version → {url:, sha256:} of the
    # .tar.xz, release versions only (no previews, no rc).
    # @return [Hash{String => Hash}]
    def self.index
      body = Net::HTTP.get URI(INDEX_URL)
      body.each_line.with_object({}) do |line, index|
        name, url, _sha1, sha256 = line.chomp.split("\t")
        version = name.to_s[/\Aruby-(\d+\.\d+\.\d+)\z/, 1]
        next unless version && url.to_s.end_with?('.tar.xz') && sha256.to_s =~ /\A[0-9a-f]{64}\z/
        index[version] = { url: url, sha256: sha256 }
      end
    end

    # The newest release of each of `lines` in the index.
    # @return [Hash{String => String}] line → version
    def self.newest_in_index lines, index = self.index
      lines.to_h { |line| [line, newest(line, index.keys)] }.compact
    end

    def name
      "ruby-#{version}"
    end

    def line
      self.class.line_of version
    end

    def abi
      self.class.abi_of version
    end

    def dataset
      self.class.dataset os_version, arch
    end

    def mountpoint
      self.class.mountpoint os_version, arch
    end

    # The release directory on a host (and, through the device, in the guests
    # under /opt/ruby/ruby-<version>).
    def dir
      "#{mountpoint}/#{name}"
    end

    def guest_dir
      "/opt/ruby/#{name}"
    end

    def snapshot
      "#{dataset}@#{name}"
    end

    # @return [Boolean] whether the release is present on the host
    def present_on? host
      success, _ = host.exec "test -x #{dir.shellescape}/bin/ruby"
      success
    end

    def snapshot_on? host
      success, _ = host.exec "zfs list -H -t snapshot -o name #{snapshot.shellescape}"
      success
    end

    def dataset_on? host
      success, _ = host.exec "zfs list -H -o name #{dataset.shellescape}"
      success
    end

    # Creates the per-(os, arch) dataset on a host when missing, and mounts
    # it when it is not (a dataset received by zfs recv, or unmounted by
    # hand, is there but empty at its mountpoint).
    def ensure_dataset_on! host
      if dataset_on? host
        success, mounted = host.exec "zfs get -H -o value mounted #{dataset.shellescape}"
        return if success && mounted.to_s.strip == 'yes'
        host.exec! "zfs mount #{dataset.shellescape}", "Failed to mount the ruby dataset #{dataset} on #{host.name}"
      else
        host.exec! "zfs create -p -o mountpoint=#{mountpoint.shellescape} #{dataset.shellescape}", "Failed to create the ruby dataset #{dataset} on #{host.name}"
      end
    end

    # The build host for the arch.
    # @raise [RuntimeError] when none is configured
    def build_host
      CloudModel::Host.build_host(arch) or raise "no build host for arch #{arch} (CloudModel.config.build_host_name)"
    end

    # Builds the release on the build host when it is not there yet and
    # snapshots the dataset as `@ruby-<version>`.
    # @return [CloudModel::Host] the build host
    def ensure_built! output: $stdout
      host = build_host
      unless present_on? host
        output.puts "  building #{name} for #{os_version} #{arch} on #{host.name} (several minutes) …"
        CloudModel::Workers::RubyBuildWorker.new(host, release: self).build!
      end
      unless snapshot_on? host
        host.exec! "zfs snapshot #{snapshot.shellescape}", "Failed to snapshot #{snapshot} on #{host.name}"
      end
      host
    end

    # Brings the release onto `host`: nothing to do when present, else the
    # snapshot is sent from the build host (incrementally when the host
    # already has the dataset with an earlier release).
    def ensure_on! host, output: $stdout
      return if present_on? host
      source = ensure_built! output: output
      if source == host
        return if present_on? host
        raise "#{name} is not on #{host.name} after the build"
      end
      output.puts "  syncing #{name} #{source.name} → #{host.name}"
      sync_zfs_dataset! source, host, dataset, snapshot: snapshot
      ensure_dataset_on! host
      raise "#{name} is not on #{host.name} after the sync" unless present_on? host
    end
  end
end
