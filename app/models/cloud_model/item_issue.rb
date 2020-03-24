module CloudModel
  module ItemIssueSubjectMapper
    def subject
      Rails.logger.debug "+++ #{subject_type}"

      if subject_type =~ /CloudModel::Services::/
        CloudModel::Guest.find_by('services'=>{'$elemMatch' =>{'_id'=>subject_id}}).services.find(subject_id)
      elsif subject_type == "CloudModel::LxdCustomVolume"
        CloudModel::Guest.find_by('lxd_custom_volumes'=>{'$elemMatch' =>{'_id'=>subject_id}}).lxd_custom_volumes.find(subject_id)
      else
        super
      end
    end
    
    def title
      result = super
      if result.blank? and key
        I18n.t "issues.#{subject_type.try :underscore}.#{key}", value: value, default: :"issues.general.#{key}"
      else
        result
      end
    end
  end
  
  class ItemIssue
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::ENumFields
    prepend CloudModel::SmartToString
    prepend ItemIssueSubjectMapper

    field :title, type: String
    field :message, type: String
    field :key, type: String
    field :value
    enum_field :severity, values: {
      0x00 => :info,
      0x01 => :task,
      0x10 => :warning,
      0xf0 => :critical,
      0xff => :fatal
    }, default: :info
    
    field :resolved_at, type: Time
    
    belongs_to :subject, optional: true, polymorphic: true
    
    after_create :notify
    
    def self.open
      scoped.where(resolved_at: nil)
    end
    
    def self.resolved
      scoped.where(:resolved_at.ne nil)
    end
    
    def name
      title
    end
    
    def resolved?
      not resolved_at.blank?
    end
    
    def notify
      CloudModel.config.monitoring_notifiers.each do |notifier|
        if notifier[:severity] and notifier[:severity].include?(severity)
          result = notifier[:notifier].send_message "[#{severity.to_s.upcase}] #{subject}: #{title}", message
        end
      end
    end
  end
end