module CloudModel
  class GuestTemplateType
    include Mongoid::Document
    include Mongoid::Timestamps
    prepend CloudModel::Mixins::SmartToString

    has_many :templates, class_name: 'CloudModel::GuestTemplate'

    #field :name, type: String
    field :components, type: Array, default: []
    field :os_version, type: String, default: "ubuntu-#{CloudModel.config.ubuntu_version}"

    def new_template host
      core_template = CloudModel::GuestCoreTemplate.where(os_version: os_version).last_useable(host)
      templates.create(
        core_template: core_template,
        os_version: os_version,
        arch: host.arch
      )
    end

    def build_new_template!(host, options={})
      template = new_template(host)
      template.build_state = :pending
      template.build! host, options
      template
    end

    def last_useable(host, options={})
      template = templates.where(arch: host.arch, build_state_id: 0xf0).last
      if template.blank? or options[:force_rebuild]
        template = build_new_template! host, options
      end
      template
    end

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