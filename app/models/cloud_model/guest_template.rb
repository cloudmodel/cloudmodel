module CloudModel
  class GuestTemplate
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::ENumFields
    prepend CloudModel::Mixins::SmartToString

    field :arch, type: String

    belongs_to :template_type, class_name: "CloudModel::GuestTemplateType"
    belongs_to :core_template, class_name: "CloudModel::GuestCoreTemplate"
    
    enum_field :build_state, {
      0x00 => :pending,
      0x01 => :running,
      0x05 => :packaging,
      0x10 => :downloading,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started

    field :build_last_issue, type: String
    
    def self.buildable_build_states
      [:finished, :failed, :not_started]
    end
        
    def buildable?
      self.class.buildable_build_states.include? build_state
    end
    
    def self.latest_created_at
      scoped.where(build_state_id: 0xf0).max(:created_at)
    end
    
    def worker host
      CloudModel::Workers::GuestTemplateWorker.new host
    end
    
    def build(host, options = {})
      unless buildable? or options[:force]
        return false
      end

      update_attribute :build_state, :pending

      begin
        CloudModel::call_rake 'cloudmodel:guest_template:build', host_id: host.id, template_id: id
      rescue Exception => e
        update_attributes build_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
      end
    end
  
    def build!(host, options={})
      unless buildable? or options[:force]
        return false
      end

      self.build_state = :pending

      worker(host).build_template self, options
    end
    
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
    
    def lxd_image_metadata_tarball
      "/cloud/templates/#{template_type_id}/#{id}.lxd.tar.gz"
    end
    
    def lxd_alias
      "#{template_type_id}/#{id}"
    end
    
    def tarball
      "/cloud/templates/#{template_type_id}/#{id}.tar.gz"
    end
  end
end
