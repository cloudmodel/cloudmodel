module CloudModel
  # Uniquely identifies a combination of software components and OS version for
  # which LXD images ({GuestTemplate}) are built.
  #
  # When a {Guest} is deployed, its required component set is resolved to a
  # GuestTemplateType. If no finished template exists for that type, a new one
  # is built automatically before deployment continues.
  class GuestTemplateType
    include Mongoid::Document
    include Mongoid::Timestamps
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [r] templates
    #   @return [Array<CloudModel::GuestTemplate>] all built images for this type
    has_many :templates, class_name: '::CloudModel::GuestTemplate'

    # @!attribute [rw] components
    #   @return [Array<Symbol>] sorted list of component symbols (e.g. `[:"nginx", :"php@8.2"]`)
    field :components, type: Array, default: []

    # @!attribute [rw] os_version
    #   @return [String] e.g. `"ubuntu-22.04.4"`
    field :os_version, type: String, default: "ubuntu-#{CloudModel.config.ubuntu_version}"

    # Creates a new {GuestTemplate} record for this type on the given host.
    # Picks the most recently finished core template for the host's arch.
    # @param host [CloudModel::Host]
    # @return [CloudModel::GuestTemplate]
    def new_template host
      core_template = CloudModel::GuestCoreTemplate.where(os_version: os_version).last_useable(host)
      templates.create(
        core_template: core_template,
        os_version: os_version,
        arch: host.arch
      )
    end

    # Creates a new template record and immediately triggers a synchronous build.
    # @param host [CloudModel::Host]
    # @param options [Hash] forwarded to the build worker
    # @return [CloudModel::GuestTemplate]
    def build_new_template!(host, options={})
      template = new_template(host)
      template.build_state = :pending
      template.build! host, options
      template
    end

    # Returns the most recently finished template for `host`'s architecture.
    # If none exists (or `force_rebuild: true`), triggers a fresh build first.
    # @param host [CloudModel::Host]
    # @param options [Hash]
    # @option options [Boolean] :force_rebuild always build a new template
    # @return [CloudModel::GuestTemplate]
    def last_useable(host, options={})
      template = templates.where(arch: host.arch, build_state_id: 0xf0).last
      if template.blank? or options[:force_rebuild]
        template = build_new_template! host, options
      end
      template
    end

    # Returns human-readable names for all components in this type.
    # @return [Array<String>] e.g. `["Nginx", "Php 8.2"]`
    def componant_names
      components.map do |c|
        begin
          CloudModel::Components::BaseComponent.from_sym(c).human_name
        rescue
          c.to_s.camelcase
        end
      end
    end

    def name
      if components.empty?
        "#{os_version} without components"
      else
        "#{os_version} with #{componant_names * ', '}"
      end
    end
  end
end