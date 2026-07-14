require 'shellwords'

module CloudModel
  module Mixins
    # Shared behaviour for templates that are built into ZFS volumes
    # ({GuestTemplate}, {GuestCoreTemplate}).
    #
    # Provides the {BuildZfsVolume} handle, an atomic build claim (so
    # concurrent deploys never build the same template twice), syncing a
    # built volume between hosts via `zfs send | zfs receive` (routed through
    # the admin machine, like the tarball scp sync before), and
    # {#ensure_build_volume!}, which gets a template volume onto a host by
    # whatever means necessary: already there → sync from another host →
    # build locally → wait for a concurrent build.
    #
    # Including classes must define `build_dataset`, `build_mountpoint`, and
    # `build_on!(host)` (dispatch to their build worker).
    module HasZfsBuildVolume
      include CloudModel::Mixins::ZfsDatasetSync

      # Terminal build states a new build may be claimed from
      # (finished, failed, not_started — see buildable_build_states)
      CLAIMABLE_BUILD_STATE_IDS = CloudModel::TERMINAL_BUILD_STATE_IDS

      def self.included(base)
        base.belongs_to :build_host, class_name: "CloudModel::Host", optional: true
      end

      # @return [String] ZFS snapshot new clones are created from
      def build_snapshot
        CloudModel::BuildZfsVolume.ready_snapshot build_dataset
      end

      # @param host [CloudModel::Host]
      # @return [CloudModel::BuildZfsVolume] this template's volume on `host`
      def build_volume host
        CloudModel::BuildZfsVolume.new host, build_dataset, mountpoint: build_mountpoint,
          compression: CloudModel.config.zfs_compression
      end

      # Atomically claims the template for building by moving `build_state`
      # from a terminal state to `:pending`. Exactly one concurrent caller
      # wins; everybody else gets false and should wait.
      # @return [Boolean] true if this caller may build
      def claim_build!
        claimed = self.class.where(:id => id, :build_state_id.in => CLAIMABLE_BUILD_STATE_IDS)
          .find_one_and_update({'$set' => {build_state_id: 0x00}})

        if claimed
          self.build_state = :pending
          true
        else
          false
        end
      end

      # Makes sure this template's volume is ready on `host`: syncs it from
      # a host that has it, builds it (claimed atomically, preferring the
      # configured build host) and syncs it over, or waits for a build
      # already running elsewhere.
      # @param host [CloudModel::Host]
      # @return [CloudModel::BuildZfsVolume] the ready volume on `host`
      # @raise [RuntimeError] when a concurrent build does not finish in time
      def ensure_build_volume! host, timeout: 2.hours
        volume = build_volume host
        deadline = Time.now + timeout

        until volume.ready?
          if Time.now > deadline
            raise "Timeout waiting for concurrent build of template #{id} (build_state #{reload.build_state})"
          end

          # While no build is running a finished copy may exist somewhere —
          # sync it over rather than rebuilding; only build when no host has
          # it. While another process builds, just wait (the host scan in
          # sync_build_volume_to costs SSH round trips per host).
          if build_claimable?
            if sync_build_volume_to host
              next
            elsif claim_build!
              # Build on the build host configured for the template's arch;
              # the next loop pass syncs the result over. Without one, build
              # directly on the target (which by definition has the arch).
              build_on! CloudModel::Host.build_host(arch) || host
              next
            end
          end

          sleep 30
        end

        volume
      end

      # True while no build of this template is running (current DB state)
      def build_claimable?
        CLAIMABLE_BUILD_STATE_IDS.include? reload.build_state_id
      end

      # Copies the ready volume from a host that has it to `target_host` via
      # `zfs send | zfs receive`, piped through the admin machine (hosts don't
      # SSH to each other — same route the tarball scp sync took).
      # @return [Boolean] true if a source was found and the sync succeeded
      def sync_build_volume_to target_host
        return false if CloudModel.config.skip_sync_images

        source_host = build_volume_source_host exclude: target_host
        return false unless source_host

        sync_zfs_dataset! source_host, target_host, build_dataset
      rescue Exception => e
        CloudModel.log_exception e
        false
      end

      # Finds a host that has this template's volume ready — the recorded
      # build host first, then the build host configured for the template's
      # arch, then all others.
      # @return [CloudModel::Host, nil]
      def build_volume_source_host exclude: nil
        hosts = ([build_host, CloudModel::Host.build_host(arch)] + CloudModel::Host.all.to_a).compact.uniq - [exclude]
        hosts.find do |host|
          begin
            build_volume(host).ready?
          rescue Exception => e
            CloudModel.log_exception e
            false
          end
        end
      end

    end
  end
end
