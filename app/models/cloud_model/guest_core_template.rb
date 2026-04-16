module CloudModel
  # A minimal base OS image (Ubuntu or Debian debootstrap) from which
  # {GuestTemplate} instances are built.
  #
  # Building a core template downloads and bootstraps a clean OS tarball onto
  # the host. Guest templates extend the core by layering software components
  # on top. Only one useable core template per `arch` + `os_version` combination
  # is typically needed at a time.
  class GuestCoreTemplate
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::ENumFields
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] os_version
    #   @return [String] e.g. `"ubuntu-22.04.4"` or `"debian-12"`
    field :os_version, type: String, default: "ubuntu-#{CloudModel.config.ubuntu_version}"

    # @!attribute [rw] arch
    #   @return [String] CPU architecture, e.g. `"amd64"`
    field :arch, type: String

    # @!attribute [r] templates
    #   @return [Array<CloudModel::GuestTemplate>] guest templates built from this core
    has_many :templates, class_name: "CloudModel::GuestTemplate"

    # @!attribute [rw] build_state
    #   @return [Symbol] one of `:pending`, `:running`, `:packaging`, `:downloading`,
    #     `:finished`, `:failed`, `:not_started`
    enum_field :build_state, {
      0x00 => :pending,
      0x01 => :running,
      0x05 => :packaging,
      0x10 => :downloading,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started

    # @!attribute [rw] build_last_issue
    #   @return [String, nil] error message from the last failed build
    field :build_last_issue, type: String

    # Returns the build states from which a new build may be started.
    # @return [Array<Symbol>]
    def self.buildable_build_states
      [:finished, :failed, :not_started]
    end

    # Returns true when a new build can be triggered.
    # @return [Boolean]
    def buildable?
      self.class.buildable_build_states.include? build_state
    end

    # Returns the creation timestamp of the most recently finished build.
    # @return [Time, nil]
    def self.latest_created_at
      scoped.where(build_state_id: 0xf0).max(:created_at)
    end

    # Creates a new GuestCoreTemplate record for the given host's architecture.
    # @param host [CloudModel::Host]
    # @param attrs [Hash] additional attributes to merge
    # @return [CloudModel::GuestCoreTemplate]
    def self.new_template_to_build host, attrs = {}
      CloudModel::GuestCoreTemplate.create attrs.merge(arch: host.arch)
    end

    def name
      "#{os_version}"
    end

    # Creates a new record for `host` and immediately triggers an async build.
    # @param host [CloudModel::Host]
    # @param options [Hash] forwarded to the build worker
    # @return [CloudModel::GuestCoreTemplate]
    def self.build!(host, options={})
      new_template_to_build(host).build! host, options
    end

    # Enqueues an async build job via ActiveJob.
    # Returns false without enqueuing if already building (unless `force: true`).
    # @param host [CloudModel::Host]
    # @param options [Hash]
    # @option options [Boolean] :force bypass deployable? check
    # @return [Boolean] false if not buildable
    def build(host, options = {})
      unless buildable? or options[:force]
        return false
      end

      update_attributes build_state: :pending, arch: host.arch

      begin
        CloudModel::GuestCoreTemplateJobs::BuildJob.perform_later id.to_s, host.id.to_s
      rescue Exception => e
        update_attributes build_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
      end
    end

    # Returns the worker instance that performs builds on `host`.
    # @param host [CloudModel::Host]
    # @return [CloudModel::Workers::GuestTemplateWorker]
    def worker host
      CloudModel::Workers::GuestTemplateWorker.new host
    end

    # Runs the build synchronously (blocking). Sets `build_state` to `:pending`
    # before handing off to the worker.
    # @param host [CloudModel::Host]
    # @param options [Hash] forwarded to the worker
    # @return [Boolean] false if not buildable
    def build!(host, options={})
      unless buildable? or options[:force]
        return false
      end

      self.build_state = :pending

      worker(host).build_core_template self, options
    end

    # Returns the most recently finished core template for the host's architecture.
    # @param host [CloudModel::Host]
    # @return [CloudModel::GuestCoreTemplate, nil]
    def self.last_useable(host, options={})
      template = self.where(arch: host.arch, build_state_id: 0xf0).last
      # unless template
      #   template = new_template_to_build host
      #   template.build_state = :pending
      #   template.build(host, options)
      # end
      # template
    end

    # Returns the path to the core template tarball on the host filesystem.
    # @return [String]
    def tarball
      "/cloud/templates/core/#{id}.tar.gz"
    end
  end
end