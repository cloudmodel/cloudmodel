module CloudModel
  module Mixins
    # Adds monitoring state tracking and issue associations to a Mongoid document.
    #
    # When included, the module adds:
    # - A polymorphic `has_many :item_issues` association ({ItemIssue} records)
    # - `monitoring_last_check_at` / `monitoring_last_check_result` fields
    # - {#state} — derives the current health state from open issues
    # - {#linked_item_issues} — finds issues anywhere in the subject chain
    #
    # Models that include this mixin should also override {#item_issue_chain}
    # to return the full ancestry path (e.g. `[host, guest, service]`) so that
    # issues bubble up correctly through the hierarchy.
    module HasIssues
      def self.included(base)
        # @!attribute [r] item_issues
        #   @return [Array<CloudModel::ItemIssue>] issues directly attached to this record
        base.has_many :item_issues, as: :subject, class_name: "CloudModel::ItemIssue"

        # @!attribute [rw] monitoring_last_check_at
        #   @return [Time, nil] timestamp of the most recent monitoring check
        base.field :monitoring_last_check_at, type: Time

        # @!attribute [rw] monitoring_last_check_result
        #   @return [Hash] raw parsed check_mk data from the most recent check
        base.field :monitoring_last_check_result, type: Hash, default: {}
        base.extend ClassMethods
      end

      module ClassMethods
      end

      # Returns the chain of records from the root host down to this object.
      # Override in subclasses to include the full ancestry.
      # @return [Array] e.g. `[host, guest, service]`
      def item_issue_chain
        [self]
      end

      # All recorded {CloudModel::MonitoringSample}s for this record. Queried by
      # polymorphic subject so it works for embedded subjects (services) too.
      # @return [Mongoid::Criteria<CloudModel::MonitoringSample>]
      def monitoring_samples
        CloudModel::MonitoringSample.where(subject_type: self.class.name, subject_id: id)
      end

      # Time-series monitoring samples for graphing, ordered by time.
      #
      # @param resolution [String] one of `raw`, `hour`, `day`
      # @param since [Time, nil] lower bound on sample time (inclusive)
      # @param until_time [Time, nil] upper bound on sample time (inclusive)
      # @return [Mongoid::Criteria<CloudModel::MonitoringSample>]
      def monitoring_history resolution: 'raw', since: nil, until_time: nil
        scope = monitoring_samples.where(resolution: resolution.to_s)
        scope = scope.gte(ref_at: since) if since
        scope = scope.lte(ref_at: until_time) if until_time
        scope.asc(:ref_at)
      end

      # Returns all {ItemIssue}s that reference this record anywhere in their
      # subject chain (not just issues where this record is the direct subject).
      # @return [Mongoid::Criteria<CloudModel::ItemIssue>]
      def linked_item_issues
        CloudModel::ItemIssue.where('subject_chain_ids': {'$elemMatch': {type: self.class.to_s, id: id}})
      end

      # Derives the current health state from open issues.
      #
      # Returns `:undefined` when no monitoring data has been collected yet,
      # `:running` when there are no open issues, or the severity symbol of the
      # most critical open issue.
      #
      # @return [Symbol] `:undefined`, `:running`, `:info`, `:warning`, `:critical`, or `:fatal`
      def state
        if monitoring_last_check_result.blank?
          :undefined
        else
          if item_issues.open.count == 0
            :running
          else
            item_issues.open.desc(:severity_id).first.severity
          end
        end
      end
    end
  end
end