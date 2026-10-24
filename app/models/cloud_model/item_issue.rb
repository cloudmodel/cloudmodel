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
        # Last fallback humanizes the key: per-device issue keys are dynamic
        # (net_eth0_rx_errs, disk_sda_await, ...) and can't be enumerated in
        # the locale files — better a readable key than "translation missing".
        I18n.t "issues.#{subject_type.try :underscore}.#{key}", value: value,
          default: [:"issues.general.#{key}", key.to_s.humanize]
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
    # @!attribute [rw] notified_at
    #   @return [Time, nil] when the notifiers were last told about this issue
    field :notified_at, type: Time
    # @!attribute [rw] notified_severity
    #   @return [String, nil] the severity that notification carried
    field :notified_severity, type: String

    SEVERITY_RANK = { info: 0, task: 1, warning: 2, critical: 3, fatal: 4 }.freeze
    # Below this an issue has to survive into the next monitoring cycle before
    # anyone is told (see .notify_due!) — most warnings are a moment's lag or
    # a slow answer and resolve themselves within one cycle.
    IMMEDIATE_SEVERITY = :critical

    after_create { notify_if_due }

    index subject_type: 1, subject_id: 1, resolved_at: 1
    index 'subject_chain_ids.type': 1, 'subject_chain_ids.id': 1, resolved_at: 1
    # TTL: resolved issues are historical records — Mongo drops them a year
    # after resolution (documents without resolved_at never expire).
    index({resolved_at: 1}, {expire_after_seconds: 1.year.to_i})

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

    # Tells the notifiers when it is time: a critical or fatal issue right
    # away, a lower one once it has been confirmed by a later cycle, and any
    # issue again when its severity rose above what was reported.
    # @param confirmed [Boolean] the issue was seen open before this cycle
    # @return [Boolean] whether a notification went out
    def notify_if_due confirmed: false
      rank = SEVERITY_RANK[severity]
      if notified_at
        return false unless rank > SEVERITY_RANK[notified_severity.to_s.to_sym].to_i
      else
        return false unless confirmed or rank >= SEVERITY_RANK[IMMEDIATE_SEVERITY]
      end
      notify
      set notified_at: Time.now, notified_severity: severity.to_s
      true
    end

    # End of a monitoring cycle: every issue that is still open and was
    # never reported has by now survived a cycle — report it. Issues that
    # resolved in between never made a sound.
    # @param older_than [ActiveSupport::Duration] how long an issue must have
    #   been open (guards against a cycle that follows a crash immediately)
    # @return [Integer] notifications sent
    def self.notify_due! older_than: 10.minutes
      open.where(notified_at: nil, :created_at.lte => Time.now - older_than).to_a.count { |issue| issue.notify_if_due confirmed: true }
    end

    # Dispatches the issue to all configured notifiers whose severity filter
    # includes this issue's severity (see #notify_if_due for the timing).
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