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

  # A monitoring event attached to any model that includes {Mixins::HasIssues}.
  #
  # Issues are created by monitoring checks and trigger notifications via the
  # configured {CloudModel::Config#monitoring_notifiers}. They remain open
  # until {#resolved_at} is set. The `subject_chain_ids` field stores the full
  # host → guest → service chain so issues can be surfaced at any level.
  class ItemIssue
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::ENumFields
    prepend CloudModel::Mixins::SmartToString
    prepend ItemIssueSubjectMapper

    # @!attribute [rw] title
    #   @return [String] short summary of the issue
    field :title, type: String

    # @!attribute [rw] message
    #   @return [String, nil] detailed description or error output
    field :message, type: String

    # @!attribute [rw] key
    #   @return [String, nil] i18n key used to generate the title when blank
    field :key, type: String

    # @!attribute [rw] value
    #   @return [Object, nil] measured value that triggered the issue (used in i18n interpolation)
    field :value

    # @!attribute [rw] severity
    #   @return [Symbol] `:info`, `:task`, `:warning`, `:critical`, or `:fatal`
    enum_field :severity, {
      0x00 => :info,
      0x01 => :task,
      0x10 => :warning,
      0xf0 => :critical,
      0xff => :fatal
    }, default: :info

    # @!attribute [rw] resolved_at
    #   @return [Time, nil] when the issue was resolved; nil means still open
    field :resolved_at, type: Time

    # @!attribute [rw] subject
    #   @return [Object, nil] the model instance this issue belongs to (polymorphic)
    belongs_to :subject, optional: true, polymorphic: true

    # @!attribute [rw] subject_chain_ids
    #   @return [Array<Hash>] ordered chain of `{type:, id:}` hashes from host down to subject
    field :subject_chain_ids, type: Array, default: []

    before_save :set_subject_chain
    after_create :notify

    index subject_type: 1, subject_id: 1, resolved_at: 1
    index 'subject_chain_ids.type': 1, 'subject_chain_ids.id': 1, resolved_at: 1

    # @return [Mongoid::Criteria] all unresolved issues
    def self.open
      scoped.where(resolved_at: nil)
    end

    # @return [Mongoid::Criteria] all resolved issues
    def self.resolved
      scoped.where(resolved_at: {"$ne" => nil})
    end

    def name
      title
    end

    # @return [Boolean] true when this issue has been resolved
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

    # After-create callback: dispatches the issue to all configured notifiers
    # whose severity filter includes this issue's severity.
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