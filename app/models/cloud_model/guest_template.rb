module CloudModel
  # A versioned LXD image for a specific {GuestTemplateType} (component set + OS).
  #
  # Each GuestTemplate is built once by installing all required components on top
  # of a {GuestCoreTemplate}. The resulting tarball is imported into LXD and
  # re-used every time a {Guest} with a matching component set is deployed,
  # avoiding repeated package installation.
  class GuestTemplate
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::ENumFields
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] os_version
    #   @return [String] e.g. `"ubuntu-22.04.4"`
    field :os_version, type: String, default: "ubuntu-#{CloudModel.config.ubuntu_version}"

    # @!attribute [rw] arch
    #   @return [String] CPU architecture, e.g. `"amd64"`
    field :arch, type: String

    # @!attribute [rw] template_type
    #   @return [CloudModel::GuestTemplateType] the component set this template satisfies
    belongs_to :template_type, class_name: "CloudModel::GuestTemplateType", optional: true

    # @!attribute [rw] core_template
    #   @return [CloudModel::GuestCoreTemplate] the base OS image this template was built on
    belongs_to :core_template, class_name: "CloudModel::GuestCoreTemplate", optional: true

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

    # @return [Array<Symbol>] build states from which a new build may be started
    def self.buildable_build_states
      [:finished, :failed, :not_started]
    end

    # @return [Boolean] true when a new build can be triggered
    def buildable?
      self.class.buildable_build_states.include? build_state
    end

    # @return [Time, nil] creation time of the most recent finished build
    def self.latest_created_at
      scoped.where(build_state_id: 0xf0).max(:created_at)
    end

    # @param host [CloudModel::Host]
    # @return [CloudModel::Workers::GuestTemplateWorker]
    def worker host
      CloudModel::Workers::GuestTemplateWorker.new host
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

      update_attribute :build_state, :pending

      begin
        CloudModel::GuestTemplateJobs::BuildJob.perform_later id.to_s, host.id.to_s
      rescue Exception => e
        update_attributes build_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
      end
    end

    # Runs the build synchronously.
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

    # Maps the stored arch to the LXD architecture string.
    # @return [String] e.g. `"x86_64"` for `"amd64"`
    def lxd_arch
      case arch
      when 'amd64'
        'x86_64'
      else
        arch
      end
    end

    def name
      if created_at
        "#{template_type.name} (#{created_at.strftime("%Y-%m-%d %H:%M:%S")})"
      else
        "#{template_type.name} (not saved)"
      end
    end

    # @return [String] path to the LXD metadata tarball on the host filesystem
    def lxd_image_metadata_tarball
      "/cloud/templates/#{template_type_id}/#{id}.lxd.tar.gz"
    end

    # @return [String] LXD image alias used when importing the template
    def lxd_alias
      "#{template_type_id}/#{id}"
    end

    # @return [String] path to the rootfs tarball on the host filesystem
    def tarball
      "/cloud/templates/#{template_type_id}/#{id}.tar.gz"
    end
  end
end
