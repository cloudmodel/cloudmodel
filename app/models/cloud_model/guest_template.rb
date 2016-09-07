module CloudModel
  class GuestTemplate
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::ENumFields

    field :arch

    belongs_to :template_type, class_name: "CloudModel::GuestTemplateType"
    belongs_to :core_template, class_name: "CloudModel::GuestCoreTemplate"
    
    enum_field :build_state, values: {
      0x00 => :pending,
      0x01 => :running,
      0x05 => :packaging,
      0x10 => :downloading,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started

    field :build_last_issue
    
    def tarball
      "/inst/templates/#{template_type_id}/#{id}.tar"
    end
  end
end
