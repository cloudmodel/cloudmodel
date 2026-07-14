require 'shellwords'

module CloudModel
  # Manages the ZFS dataset a guest template is built in on a build host.
  #
  # Template builds run inside a dedicated dataset instead of a plain build
  # directory, so a finished build can be committed as a snapshot and deployed
  # to containers via `zfs clone` — no tarball packing, syncing, or unpacking.
  #
  # The dataset carries a `com.cloudmodel:status` user property
  # (building/ready/failed) so builds are introspectable on the host itself.
  # Concurrent builds are prevented by the template's build_state in MongoDB,
  # not here.
  class BuildZfsVolume
    # Snapshot name marking a finished, deployable build
    READY_SNAPSHOT = 'ready'

    # @return [String] the ready snapshot of the given dataset
    def self.ready_snapshot(dataset)
      "#{dataset}@#{READY_SNAPSHOT}"
    end

    attr_reader :host, :dataset_name, :mountpoint, :compression

    # @param compression [String, nil] ZFS compression to create the dataset
    #   with (e.g. "zstd"); nil inherits the parent/pool setting. Web-image
    #   artifacts set "zstd" — it roughly matches the old tar.bz2 size (~3.2x)
    #   transparently, and clones/send streams stay small.
    def initialize(host, dataset_name, mountpoint:, compression: nil)
      @host = host
      @dataset_name = dataset_name
      @mountpoint = mountpoint
      @compression = compression
    end

    # ZFS create/clone options shared by prepare! / prepare_from!.
    def create_opts
      opts = "-o mountpoint=#{@mountpoint.shellescape}"
      opts += " -o compression=#{@compression.shellescape}" unless @compression.to_s.empty?
      opts
    end

    # The template's rootfs inside the volume; mirrors the LXD container
    # dataset layout (rootfs/ beside metadata.yaml), so a committed build can
    # be cloned straight to a container volume.
    def rootfs_path
      "#{@mountpoint}/rootfs"
    end

    # Creates a fresh dataset for a new build. A leftover dataset from a
    # previous (failed or superseded) build is destroyed first.
    def prepare!
      destroy!
      execute "zfs create -p #{create_opts} #{@dataset_name.shellescape}"
      set_status 'building'
    end

    # Clones the ready snapshot of another build dataset (e.g. the core
    # template's) as the starting point for this build.
    def prepare_from!(source_dataset)
      unless snapshot_exists? source_dataset
        raise "Source ZFS snapshot #{source_dataset}@#{READY_SNAPSHOT} does not exist on host"
      end
      destroy!
      execute "zfs clone -p #{create_opts} #{"#{source_dataset}@#{READY_SNAPSHOT}".shellescape} #{@dataset_name.shellescape}"
      set_status 'building'
    end

    # Snapshots the finished build as deployable. An existing ready snapshot
    # (forced rebuild) is replaced.
    def commit!
      if snapshot_exists? @dataset_name
        execute "zfs destroy #{ready_snapshot.shellescape}"
      end
      execute "zfs snapshot #{ready_snapshot.shellescape}"
      set_status 'ready'
    end

    # True if the dataset carries a committed ready snapshot, i.e. it can be
    # cloned to containers on this host. (A snapshot implies its dataset, so
    # one probe suffices — this is the hottest check in the deploy path.)
    def ready?
      snapshot_exists? @dataset_name
    end

    # Marks a broken build; the dataset is kept for inspection and destroyed
    # by the next prepare!.
    def fail!
      set_status 'failed' if dataset_exists?
    end

    def destroy!
      return unless dataset_exists?
      if mounted?
        # -R also clears stray sub-mounts (e.g. chroot proc/sys/dev binds left
        # by a crashed build) which would make the destroy fail with EBUSY
        @host.exec "umount -R #{@mountpoint.shellescape}"
      end
      execute "zfs destroy -r #{@dataset_name.shellescape}"
    end

    # Strips identity data that must not be shared between containers cloned
    # from this volume: SSH host keys (regenerated on first boot or written by
    # the SSH service worker on deploy) and the machine-id (an empty file
    # makes systemd generate one on boot). Shared by template builds and the
    # tarball migration.
    def scrub_identity!
      execute "rm -f #{rootfs_path}/etc/ssh/ssh_host_*"
      execute "rm -f #{rootfs_path}/etc/machine-id #{rootfs_path}/var/lib/dbus/machine-id && touch #{rootfs_path}/etc/machine-id"
    end

    def mount!
      execute "zfs mount #{@dataset_name.shellescape}" unless mounted?
    end

    def unmount!
      execute "zfs unmount #{@dataset_name.shellescape}" if mounted?
    end

    def mounted?
      capture("zfs get -H -o value mounted #{@dataset_name.shellescape}") == 'yes'
    end

    def dataset_exists?
      @host.exec("zfs list #{@dataset_name.shellescape}").first
    end

    def ready_snapshot
      self.class.ready_snapshot @dataset_name
    end

    private

    def snapshot_exists?(dataset)
      @host.exec("zfs list -t snapshot #{self.class.ready_snapshot(dataset).shellescape}").first
    end

    def execute(command)
      @host.exec! command, "ZFS command failed: #{command}"
    end

    def capture(command)
      success, output = @host.exec(command)
      success ? output.to_s.strip : ''
    end

    def set_status(status)
      execute "zfs set com.cloudmodel:status=#{status.shellescape} #{@dataset_name.shellescape}"
    end
  end
end
