module CloudModel
  # Raised by {Guest#backup} when one or more of a guest's service or volume
  # backups fail. Turning a failed backup into a raised error (instead of a
  # falsey return value) lets {Guest.backup_all} surface it via logging and
  # ExceptionNotification instead of swallowing it silently.
  class BackupError < StandardError
  end
end
