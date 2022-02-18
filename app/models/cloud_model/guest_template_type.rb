module CloudModel
  class GuestTemplateType
    include Mongoid::Document
    include Mongoid::Timestamps
    prepend CloudModel::Mixins::SmartToString

    has_many :templates, class_name: 'CloudModel::GuestTemplate'

    field :name, type: String
    field :components, type: Array, default: []

    def new_template host
      core_template = CloudModel::GuestCoreTemplate.last_useable(host)
      templates.create(
        core_template: core_template,
        arch: core_template.arch
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
        "CloudModel Guest Template without components"
      else
        "CloudModel Guest Template with #{componant_names * ', '}"
      end
    end
  end
end