module CloudModel
  module ItemIssueSubjectMapper
    def subject
      Rails.logger.debug "+++ #{subject_type}"

      if subject_type =~ /CloudModel::Services::/
        begin
          CloudModel::Guest.find_by('services'=>{'$elemMatch' =>{'_id'=>subject_id}}).services.find(subject_id)
        rescue
          nil
        end
      elsif subject_type == "CloudModel::LxdCustomVolume"
        begin
          CloudModel::Guest.find_by('lxd_custom_volumes'=>{'$elemMatch' =>{'_id'=>subject_id}}).lxd_custom_volumes.find(subject_id)
        rescue
          nil
        end
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
    include CloudModel::Mixins::ENumFields
    prepend CloudModel::Mixins::SmartToString
    prepend ItemIssueSubjectMapper

    field :title, type: String
    field :message, type: String
    field :key, type: String
    field :value
    enum_field :severity, {
      0x00 => :info,
      0x01 => :task,
      0x10 => :warning,
      0xf0 => :critical,
      0xff => :fatal
    }, default: :info

    field :resolved_at, type: Time

    belongs_to :subject, optional: true, polymorphic: true
    field :subject_chain_ids, type: Array, default: []

    before_save :set_subject_chain
    after_create :notify

    index subject_type: 1, subject_id: 1, resolved_at: 1
    index 'subject_chain_ids.type': 1, 'subject_chain_ids.id': 1, resolved_at: 1

    def self.open
      scoped.where(resolved_at: nil)
    end

    def self.resolved
      scoped.where(resolved_at: {"$ne" => nil})
    end

    def name
      title
    end

    def resolved?
      not resolved_at.blank?
    end

    def subject_chain= chain
      chain_ids = []
      chain.each do |link|
        chain_ids << {
          type: link.class.to_s,
          id: link.id
        }
      end
      self.subject_chain_ids = chain_ids
    end

    def subject_chain
      subject_chain_ids.map do |link|
        begin
          link[:type].constantize.find link[:id]
        rescue
          ItemIssue.new(subject_type: link[:type], subject_id: link[:id]).subject
        end
      end
    end

    def set_subject_chain
      if subject
        if subject.respond_to? :item_issue_chain
          self.subject_chain = subject.item_issue_chain
        else
          self.subject_chain = [subject]
        end
      end
    end

    def notify
      CloudModel.config.monitoring_notifiers.each do |notifier|
        if notifier[:severity] and notifier[:severity].include?(severity)
          options = {}

          m = message.to_s

          unless subject_chain_ids.blank?
            m = "#{subject_chain.map(&:to_s) * ', '}\n\n" + m
          end

          if CloudModel.config.issue_url
            url = CloudModel.config.issue_url.gsub '%id%', id.to_s

            m += "\n<#{url}>"
          end

          result = notifier[:notifier].send_message "[#{severity.to_s.upcase}] #{subject ? "#{subject}: " : ''}#{title}", m
        end
      end
    end
  end
end