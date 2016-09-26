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
    
    def self.buildable_build_states
      [:finished, :failed, :not_started]
    end
    
    def buildable?
      self.class.buildable_build_states.include? build_state
    end
    
    def build(host, options = {})
      unless buildable? or options[:force]
        return false
      end

      update_attribute :build_state, :pending

      begin
        CloudModel::call_rake 'cloudmodel:guest_template:build', host_id: host.id, template_id: id
      rescue Exception => e
        template.update_attributes build_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
      end
    end
  
    def build!(host, options={})
      guest_template_worker = CloudModel::GuestTemplateWorker.new host
      guest_template_worker.build_template self, options
    end
    
    def tarball
      "/inst/templates/#{template_type_id}/#{id}.tar"
    end
  end
end
