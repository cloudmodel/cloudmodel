module CloudModel
  # Back up a single subject (replica set, service or LXD custom volume) on
  # demand — triggered from the admin backups UI. Takes the same machine-wide
  # lock as the nightly rake run (waiting for it instead of aborting) and
  # tracks itself as a one-subject BackupRun, so the manual backup shows up in
  # the run card with live log and progress.
  #
  # A failed backup is logged and reflected in the subject's backup_state and
  # the run's success flag — it does NOT raise, so delayed_job will not retry
  # a heavy dump automatically.
  class BackupJob < CloudModel::BaseJob
    def perform(subject_type, subject_id, guest_id = nil)
      subject = self.class.resolve_subject subject_type, subject_id, guest_id
      unless subject
        Rails.logger.error "BackupJob: subject #{subject_type} #{subject_id} not found"
        return
      end

      CloudModel::BackupRun.with_file_lock do
        run = CloudModel::BackupRun.start! total_subjects: 1
        CloudModel.current_backup_run = run
        success = false
        begin
          CloudModel.with_backup_label subject_label(subject) do
            started = Time.now
            success = subject.backup_with_state
            CloudModel.backup_log success ? "backup done (#{(Time.now - started).round}s)" : 'backup FAILED'
          end
        rescue => e
          CloudModel.backup_log "backup FAILED: #{e.message}"
          if defined?(ExceptionNotifier)
            ExceptionNotifier.notify_exception e, data: {subject_type: subject_type, subject_id: subject_id.to_s}
          end
        ensure
          run.subject_finished!
          run.finish! success: success
          CloudModel.current_backup_run = nil
        end
      end
    end

    # Same subject addressing as the backups UI (destroy_backup & backup).
    # @return [CloudModel::MongodbReplicationSet, CloudModel::Services::Base,
    #   CloudModel::LxdCustomVolume, nil]
    def self.resolve_subject(subject_type, subject_id, guest_id = nil)
      case subject_type.to_s
      when 'replication_set'
        CloudModel::MongodbReplicationSet.find subject_id
      when 'service'
        CloudModel::Guest.find(guest_id).services.find subject_id
      when 'volume'
        CloudModel::Guest.find(guest_id).lxd_custom_volumes.find subject_id
      end
    rescue Mongoid::Errors::DocumentNotFound
      nil
    end

    private

    def subject_label(subject)
      case subject
      when CloudModel::MongodbReplicationSet then subject.name
      when CloudModel::LxdCustomVolume then "#{subject.guest.name} #{subject.mount_point}"
      else "#{subject.guest.name} #{subject.name}"
      end
    end
  end
end
