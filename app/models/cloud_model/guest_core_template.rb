module CloudModel  
  class GuestCoreTemplate
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::ENumFields
        
    field :os_version
    field :arch
    
    has_many :guest_templates, class_name: "CloudModel::GuestTemplate"
        
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
    
    def self.last_useable(host, options={})
      template = self.where(arch: host.arch, build_state_id: 0xf0).last
      unless template
        guest_worker = CloudModel::GuestTemplateWorker.new host
        template = guest_worker.build_core_template options
      end
      template
    end
    
    def tarball
      "/inst/templates/core/#{id}.tar"
    end
  end
end