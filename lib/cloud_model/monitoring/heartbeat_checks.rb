module CloudModel
  module Monitoring
    # Watchdog for the monitoring itself: each admin host running the
    # monitoring checks the heartbeats of the others. A host whose last
    # completed cycle is older than {MAX_AGE} gets a subject-less critical
    # issue (reported at once, like any critical issue), resolved when that
    # host completes a cycle again. Two hosts watching each other cover the
    # case this is for — one of them hanging on dead connections.
    class HeartbeatChecks
      MAX_AGE = 3.hours

      def self.check
        now = Time.now
        CloudModel::MonitoringHeartbeat.peers(now: now).each do |heartbeat|
          key = "monitoring_stale_#{heartbeat.host_name}"
          issue = CloudModel::ItemIssue.find_or_initialize_by key: key, resolved_at: nil, subject: nil

          if heartbeat.stale? max_age: MAX_AGE, now: now
            age = heartbeat.finished_at ? ((now - heartbeat.finished_at) / 3600).round(1) : nil
            puts "[_Monitoring_] \e[31m! Monitoring on #{heartbeat.host_name} has not completed a cycle for #{age ? "#{age} h" : 'ever'}\e[39m"
            existed = issue.persisted?
            issue.severity = :critical
            issue.title = "Monitoring on #{heartbeat.host_name} stalled"
            issue.message = "Last completed cycle: #{heartbeat.finished_at || 'none'}; last cycle started: #{heartbeat.started_at || 'none'}"
            issue.value = age ? "#{age} h" : 'never'
            issue.save
            issue.notify_if_due confirmed: existed if existed
          else
            puts "[_Monitoring_] Monitoring on #{heartbeat.host_name} completed a cycle #{((now - heartbeat.finished_at) / 60).round} min ago"
            if issue.persisted?
              issue.resolved_at = now
              issue.save
            end
          end
        end
        true
      end
    end
  end
end
