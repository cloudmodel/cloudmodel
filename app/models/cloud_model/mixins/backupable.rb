module CloudModel
  module Mixins
    # Tracks when backups were enabled on a model via a `backups_enabled_at`
    # timestamp. Monitoring uses it to grant a grace period before the first
    # scheduled backup has run, so enabling backups does not immediately raise a
    # "no successful backup" alert before the nightly backup job fires.
    #
    # Also carries the backup lifecycle state (`backup_state` +
    # `backup_state_at`: queued / running / success / failed) written around
    # every backup, so the admin UI can mark running and failed subjects.
    module Backupable
      def self.included(base)
        base.field :backups_enabled_at, type: Time
        base.field :backup_state, type: String
        base.field :backup_state_at, type: Time
        base.before_save :track_backups_enabled_at
      end

      # Persist the backup lifecycle state. Uses an atomic $set (no
      # validations, no timestamps) — backups run in parallel workers and this
      # bookkeeping must neither clobber concurrent writes nor ever fail a
      # backup that actually succeeded.
      def update_backup_state state
        self.backup_state = state
        self.backup_state_at = Time.now
        set backup_state: backup_state, backup_state_at: backup_state_at
      rescue => e
        Rails.logger.warn "Could not record backup state: #{e.message}"
      end

      # Run {#backup} with the persisted state around it: running while the
      # backup executes, then success/failed. An exception counts as failed
      # and is re-raised for the caller's error handling.
      # @return [Boolean] whether the backup succeeded
      def backup_with_state
        update_backup_state 'running'
        success = false
        begin
          success = backup
        ensure
          update_backup_state success ? 'success' : 'failed'
        end
        success
      end

      # Currently backing up (or waiting in the delayed_job queue)? A stale
      # `running` left behind by a killed process no longer counts after a day.
      def backup_active?
        %w(queued running).include?(backup_state) &&
          backup_state_at && backup_state_at > 24.hours.ago
      end

      private

      # Stamp (or clear) backups_enabled_at whenever the has_backups flag flips.
      def track_backups_enabled_at
        return unless has_backups_changed?
        self.backups_enabled_at = has_backups? ? Time.now : nil
      end
    end
  end
end
