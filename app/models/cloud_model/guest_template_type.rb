module CloudModel
  class GuestTemplateType
    include Mongoid::Document
    include Mongoid::Timestamps

    has_many :templates, class_name: 'CloudModel::GuestTemplate'
    
    field :name
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
  end
end