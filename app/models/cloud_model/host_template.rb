module CloudModel
  # A Debian-based OS image built for use as the base system on a {Host}.
  #
  # Unlike {GuestCoreTemplate} (which is Ubuntu/Debian for guest containers),
  # HostTemplate is the bootstrap image installed onto bare-metal or VM hosts
  # during initial provisioning. The tarball is stored on the build host's
  # local filesystem under `/cloud/templates/host/`.
  class HostTemplate
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::ENumFields
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] os_version
    #   @return [String] e.g. `"debian-12"`
    field :os_version, type: String, default: "debian-#{CloudModel.config.debian_version}"

    # @!attribute [rw] arch
    #   @return [String] CPU architecture, e.g. `"amd64"`
    field :arch, type: String

    # @!attribute [r] templates
    #   @return [Array<CloudModel::GuestTemplate>] guest templates derived from this host template
    has_many :templates, class_name: "CloudModel::GuestTemplate"

    # @!attribute [rw] build_state
    #   @return [Symbol] `:pending`, `:running`, `:packaging`, `:downloading`,
    #     `:finished`, `:failed`, or `:not_started`
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

    # @return [Array<Symbol>] build states from which a new build may be triggered
    def self.buildable_build_states
      [:finished, :failed, :not_started]
    end

    # @return [Boolean] true when a new build can be triggered
    def buildable?
      self.class.buildable_build_states.include? build_state
    end

    # @return [Time, nil] creation time of the most recently finished build
    def self.latest_created_at
      scoped.where(build_state_id: 0xf0).max(:created_at)
    end

    # Creates a new HostTemplate record for the given host's architecture.
    # @param host [CloudModel::Host]
    # @return [CloudModel::HostTemplate]
    def self.new_template_to_build host
      CloudModel::HostTemplate.create arch: host.arch
    end

    # Creates a new record and immediately triggers a synchronous build.
    # @param host [CloudModel::Host]
    # @param options [Hash] forwarded to the build worker
    # @return [CloudModel::HostTemplate]
    def self.build!(host, options={})
      new_template_to_build(host).build! host, options
    end

    # Enqueues an async build job. Returns false if not buildable.
    # @param host [CloudModel::Host]
    # @param options [Hash]
    # @option options [Boolean] :force bypass buildable? check
    # @return [Boolean]
    def build(host, options = {})
      unless buildable? or options[:force]
        return false
      end

      update_attributes build_state: :pending, arch: host.arch

      begin
        CloudModel::HostTemplateJobs::BuildJob.perform_later id.to_s, host.id.to_s
      rescue Exception => e
        update_attributes build_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
      end
    end

    # @param host [CloudModel::Host]
    # @return [CloudModel::Workers::HostTemplateWorker]
    def worker host
      CloudModel::Workers::HostTemplateWorker.new host
    end

    # Runs the build synchronously (blocking).
    # @param host [CloudModel::Host]
    # @param options [Hash] forwarded to the worker
    # @return [Boolean]
    def build!(host, options={})
      unless buildable? or options[:force]
        return false
      end

      self.build_state = :pending

      worker(host).build_template self, options
    end

    # Returns the most recently finished template for the host's architecture,
    # building a new one synchronously if none exists.
    # @param host [CloudModel::Host]
    # @return [CloudModel::HostTemplate]
    def self.last_useable(host, options={})
      template = self.where(arch: host.arch, build_state_id: 0xf0).last
      unless template
        template = new_template_to_build host
        template.build_state = :pending
        template.build!(host, options)
      end
      template
    end

    # @return [String] path to the host template tarball on the build host filesystem
    def tarball
      "/cloud/templates/host/#{id}.tar.gz"
    end
  end
end