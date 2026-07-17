module CloudModel
  module Monitoring
    module Services
      # The Backup service performs backups; it has no dedicated health probe of
      # its own. Backup *freshness* of backupable subjects is checked centrally
      # in {CloudModel::Monitoring::ServiceChecks#check_backup_freshness}, so
      # this class only needs to exist to satisfy the per-service check lookup
      # (which otherwise raises the historical :no_check info issue).
      class BackupChecks < CloudModel::Monitoring::Services::BaseChecks
        def check
        end
      end
    end
  end
end
