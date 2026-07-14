module CloudModel
  # A deployable Rails/Ruby web application built from a Git repository.
  #
  # The build clones the repository, then runs `bundle install`, `yarn install`
  # and `assets:precompile` inside a chroot on a per-arch build host (a
  # throwaway CoW clone of the consuming guest's {GuestTemplate}, which carries
  # Ruby/Rust/Node and the exact runtime libraries). The finished app tree is
  # committed as a ZFS `@ready` snapshot — one artifact per `(template, arch)`,
  # since native extensions link against the template's libs and the CPU arch.
  # Deploy `zfs clone`s that snapshot and attaches it to the guest's LXD
  # container at `/var/www/rails` — no tarball is packed, stored or unrolled.
  #
  # Two separate state machines are tracked: {#build_state} for the build and
  # {#redeploy_state} for rolling the new artifact out to guests.
  class WebImage
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::UsedInGuestsAs
    include CloudModel::Mixins::ENumFields
    include CloudModel::Mixins::HasIssues
    include CloudModel::Mixins::ZfsDatasetSync
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] name
    #   @return [String] unique human-readable label
    field :name, type: String

    # @!attribute [rw] git_server
    #   @return [String] hostname or IP of the Git server
    field :git_server, type: String

    # @!attribute [rw] git_repo
    #   @return [String] repository path on the Git server
    field :git_repo, type: String

    # @!attribute [rw] git_branch
    #   @return [String] branch to build from (default: `"master"`)
    field :git_branch, type: String, default: 'master'

    # @!attribute [rw] git_commit
    #   @return [String, nil] SHA of the last built commit (set after a successful build)
    field :git_commit, type: String

    # @!attribute [rw] ruby_version
    #   @return [String, nil] the Ruby the app is built against and runs on. This
    #   is the single source of truth for the version — it selects the build
    #   environment and the Nginx/Passenger runtime must install the SAME exact
    #   version. nil → fall back to the build host's/template's Ruby.
    field :ruby_version, type: String, default: nil

    # @!attribute [rw] has_assets
    #   @return [Boolean] whether to run the Rails asset pipeline during build
    field :has_assets, type: Mongoid::Boolean, default: false

    # @!attribute [rw] has_mongodb
    #   @return [Boolean] whether the application uses MongoDB (wires up mongoid config)
    field :has_mongodb, type: Mongoid::Boolean, default: false

    # @!attribute [rw] has_redis
    #   @return [Boolean] whether the application uses Redis
    field :has_redis, type: Mongoid::Boolean, default: false

    # @!attribute [rw] master_key
    #   @return [String, nil] Rails `RAILS_MASTER_KEY` value (32 hex chars); encrypted credentials support
    field :master_key, type: String, default: nil

    # @!attribute [rw] additional_components
    #   @return [Array<Symbol>] extra component symbols required beyond the guest's defaults
    field :additional_components, type: Array, default: []

    # @!attribute [rw] artifact_sizes
    #   @return [Hash{String=>Integer}] exclusive ZFS usage in bytes (`zfs used`)
    #     of each built artifact, keyed by "<template_id>-<arch>". Recorded at
    #     the end of the build; only space private to the artifact is counted
    #     (the shared template snapshot is excluded).
    field :artifact_sizes, type: Hash, default: {}

    # @!attribute [rw] artifact_versions
    #   @return [Hash{String=>String}] current artifact snapshot version per
    #     "<template_id>-<arch>" (a timestamp). Each build snapshots the
    #     persistent workspace as `@v<ts>` instead of destroying a fixed
    #     `@ready` — so a rebuild never has to destroy a snapshot that deployed
    #     guests still clone from (ZFS forbids that). Deploys clone the current
    #     version; old versions are pruned once no guest clones them.
    field :artifact_versions, type: Hash, default: {}

    # @!attribute [rw] mongodb_backup_exclude_collection_prefixes
    #   @return [Array<String>] collection-name prefixes this app's transient
    #     data uses (e.g. GridFS bucket `fs`, `search_journal`,
    #     `index_collection`); excluded from MongoDB replica-set backups.
    #     Passed to the associated {MongodbReplicationSet}.
    field :mongodb_backup_exclude_collection_prefixes, type: Array, default: []

    # Accept a whitespace/comma-separated string from forms as well as an array.
    def mongodb_backup_exclude_collection_prefixes=(value)
      value = value.split(/[\s,]+/) if value.is_a?(String)
      super(Array(value).map { |v| v.to_s.strip }.reject(&:blank?))
    end

    enum_field :build_state, {
      0x00 => :pending,
      0x01 => :running,
      0x02 => :checking_out,
      0x03 => :bundling,
      0x04 => :building_assets,
      0x05 => :packaging,
      0x06 => :storing,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started

    field :build_last_issue, type: String

    # @!attribute [rw] build_log
    #   @return [String] streamed output of the current/last build (reset at
    #     build start, appended live by the worker; capped in size)
    field :build_log, type: String

    enum_field :redeploy_state, {
      0x00 => :pending,
      0x01 => :running,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started

    field :redeploy_last_issue, type: String

    validates :name, presence: true, uniqueness: true
    validates :git_server, presence: true
    validates :git_repo, presence: true
    validates :git_branch, presence: true
    validates :master_key, length: {is: 32}, allow_blank: true

    used_in_guests_as 'services.deploy_web_image_id'

    # Max stored build/rollout log size; beyond it appends are dropped with a
    # single truncation marker (protects the Mongo document size).
    BUILD_LOG_LIMIT = 512 * 1024

    # Appends streamed output to the build/rollout log — one console for the
    # whole rebuild & redeploy flow, readable live on the admin page. Called
    # from the build worker (command output) and the service workers (rollout
    # steps).
    def append_to_build_log text
      # Worker output can arrive as ASCII-8BIT (Net::SSH) or carry stray
      # non-UTF-8 bytes; scrub to valid UTF-8 so concatenation with the log
      # never raises Encoding::CompatibilityError.
      text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub('?')
      return if text.empty?

      log = build_log.to_s
      if log.bytesize > BUILD_LOG_LIMIT
        return if log.end_with? "[log truncated]\n"
        text = "…\n[log truncated]\n"
      end

      update_attribute :build_log, log + text
    end

    def services
      services = []
      used_in_guests.each do |guest|
        guest.services.where('deploy_web_image_id': id).each do |service|
          services << service
        end
      end
      services
    end

    # Local (admin-side) directory the git checkout lives in. The repository
    # is cloned here — where the github deploy credentials are — and the source
    # tree is then transferred to the build host for the native chroot build.
    def build_path
      Pathname.new(CloudModel.config.data_directory).join('build', 'web_images', id).to_s
    end

    # ---- ZFS app artifact, one per (template, arch) ----
    # The built Rails app tree, committed as an @ready snapshot and cloned into
    # guests on deploy. Native extensions link against the template's libs and
    # the CPU arch, so the artifact is keyed by both.

    def build_dataset(template, arch)
      "#{CloudModel.config.build_dataset}/web/#{id}/#{template.id}-#{arch}"
    end

    def build_mountpoint(template, arch)
      "/cloud/build/web/#{id}/#{template.id}-#{arch}"
    end

    def artifact_key(template, arch)
      "#{template.id}-#{arch}"
    end

    # Current artifact snapshot version (timestamp) for (template, arch), or nil.
    def artifact_version(template, arch)
      artifact_versions[artifact_key(template, arch)]
    end

    # The current deployable snapshot: `<workspace>@v<ts>`. nil until built.
    # Each build snapshots the persistent workspace under a fresh `@v<ts>`
    # rather than a fixed `@ready`, so a rebuild never destroys a snapshot a
    # deployed guest still clones from.
    def build_snapshot(template, arch)
      ver = artifact_version(template, arch)
      ver && "#{build_dataset(template, arch)}@v#{ver}"
    end

    # @return [CloudModel::BuildZfsVolume] this image's persistent build
    #   workspace on `host` (kept across builds so bundle/node_modules/git
    #   caches make rebuilds incremental).
    def build_volume(host, template, arch)
      CloudModel::BuildZfsVolume.new host, build_dataset(template, arch),
        mountpoint: build_mountpoint(template, arch),
        compression: CloudModel.config.zfs_compression
    end

    # True if the current artifact version's snapshot exists on `host`.
    def web_volume_ready?(host, template, arch)
      snap = build_snapshot(template, arch)
      snap && host.exec("zfs list -t snapshot #{snap.shellescape}").first
    end

    # Records the freshly built artifact version (timestamp) for (template, arch).
    def record_artifact_version(template, arch, ts)
      self.artifact_versions = artifact_versions.merge(artifact_key(template, arch) => ts.to_s)
      set artifact_versions: artifact_versions
    end

    def worker(host)
      CloudModel::Workers::WebImageWorker.new host, self
    end

    # Records a built artifact's ZFS size (bytes), queried once at the end of
    # the build so detail pages never need a live host query.
    def record_artifact_size(template, arch, bytes)
      self.artifact_sizes = artifact_sizes.merge(artifact_key(template, arch) => bytes.to_i)
      set artifact_sizes: artifact_sizes
    end

    # Total ZFS size (bytes) across all built (template, arch) artifacts.
    def total_artifact_usage
      artifact_sizes.values.map(&:to_i).sum
    end

    # Per-(template, arch) breakdown of the built artifacts for detail views.
    # Each entry: { key:, template:, template_id:, arch:, version:, size: }.
    # The artifact key is "<template_id>-<arch>"; arch never contains a hyphen
    # and template_id is a bare ObjectId, so the last hyphen splits them.
    def artifact_list
      (artifact_versions.keys | artifact_sizes.keys).sort.map do |key|
        template_id, _, arch = key.rpartition('-')
        {
          key: key,
          template_id: template_id,
          template: CloudModel::GuestTemplate.where(id: template_id).first,
          arch: arch,
          version: artifact_versions[key],
          size: artifact_sizes[key].to_i
        }
      end
    end

    # The distinct [template, arch] pairs this image must be built for, derived
    # from the guests whose services deploy it.
    def build_targets
      services.map do |service|
        guest = service.guest
        next unless guest and (template = guest.template) and (host = guest.host)
        [template, host.arch]
      end.compact.uniq
    end

    # Ensures the current artifact version for (template, arch) is present on
    # `host`: already there → sync it from a host that has it → build it on the
    # arch's build host and sync it over.
    # @return [Boolean] true if the artifact snapshot is on `host`
    def ensure_web_volume!(host, template, arch, options = {})
      return true if web_volume_ready?(host, template, arch)
      return true if sync_web_volume_to(host, template, arch) && web_volume_ready?(host, template, arch)

      build_host = CloudModel::Host.build_host(arch) || host
      worker(build_host).build_app_volume template, arch, options
      sync_web_volume_to host, template, arch unless web_volume_ready?(host, template, arch)
      web_volume_ready?(host, template, arch)
    end

    # Copies the current artifact version's snapshot from a host that already
    # has it to `target_host` (via {ZfsDatasetSync#sync_zfs_dataset!}).
    # @return [Boolean] true if a source was found and the sync succeeded
    def sync_web_volume_to(target_host, template, arch)
      return false if CloudModel.config.skip_sync_images
      snap = build_snapshot(template, arch)
      return false unless snap

      candidates = ([CloudModel::Host.build_host(arch)] + CloudModel::Host.all.to_a).compact.uniq - [target_host]
      source_host = candidates.find do |host|
        begin
          host.exec("zfs list -t snapshot #{snap.shellescape}").first
        rescue Exception => e
          CloudModel.log_exception e
          false
        end
      end
      return false unless source_host

      sync_zfs_dataset! source_host, target_host, build_dataset(template, arch), snapshot: snap
    rescue Exception => e
      CloudModel.log_exception e
      false
    end

    def self.build_state_id_for build_state
      enum_fields[:build_state][:values].invert[build_state]
    end

    def self.buildable_build_states
      [:finished, :failed, :not_started]
    end

    def self.buildable_build_state_ids
      buildable_build_states.map{|s| build_state_id_for s}
    end

    def buildable?
      self.class.buildable_build_states.include? build_state
    end

    def self.buildable
      scoped.where :build_state_id.in => buildable_build_state_ids
    end

    def build(options = {})
      unless buildable? or options[:force]
        return false
      end

      update_attribute :build_state, :pending

      begin
        CloudModel::WebImageJobs::BuildJob.perform_later id.to_s
      rescue Exception => e
        update_attributes build_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
      end
    end

    def build!(options = {})
      unless buildable? or options[:force]
        return false
      end

      self.build_state = :pending

      targets = build_targets
      if targets.empty?
        update_attributes build_state: :failed, build_last_issue: 'No guest uses this web image — nothing to build for.'
        return false
      end

      targets.each do |template, arch|
        host = CloudModel::Host.build_host(arch)
        unless host
          update_attributes build_state: :failed, build_last_issue: "No build host configured for arch '#{arch}'."
          return false
        end
        worker(host).build_app_volume template, arch, options
      end

      true
    end

    def self.redeployable_redeploy_states
      [:finished, :failed, :not_started]
    end

    def redeployable?
      self.class.redeployable_redeploy_states.include? redeploy_state
    end

    def redeploy(options = {})
      unless redeployable? or options[:force]
        return false
      end

      update_attribute :redeploy_state, :pending

      services.each do |service|
        if service.redeployable? or options[:force]
          service.update_attribute :redeploy_web_image_state, :pending
        end
      end

      begin
        CloudModel::WebImageJobs::RedeployJob.perform_later id.to_s
      rescue Exception => e
        update_attributes redeploy_state: :failed, redeploy_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
      end
    end

    def redeploy!(options = {})
      unless redeployable? or options[:force]
        return false
      end

      self.redeploy_state = :pending

      services.each do |service|
        if service.redeployable? or options[:force]
          service.redeploy_web_image_state = :pending
        end
      end

      # Redeploy rolls the already-built artifact out per service (each on its
      # own guest/host); it needs no single build host of its own.
      worker(nil).redeploy options
    end
  end
end
