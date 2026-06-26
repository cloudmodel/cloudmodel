module CloudModel
  module Mixins
    # Tracks when backups were enabled on a model via a `backups_enabled_at`
    # timestamp. Monitoring uses it to grant a grace period before the first
    # scheduled backup has run, so enabling backups does not immediately raise a
    # "no successful backup" alert before the nightly backup job fires.
    module Backupable
      def self.included(base)
        base.field :backups_enabled_at, type: Time
        base.before_save :track_backups_enabled_at
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
