module CloudModel
  module Monitoring
    module Services
      # Checks for the Rake scheduled-task service. Intentionally does NOT
      # re-alert on a plain "unit failed" — that is already covered by the
      # guest-level failed-units check. It focuses on the gaps that check
      # cannot see: last-run result/freshness and a silently stalled timer.
      class RakeChecks < CloudModel::Monitoring::Services::BaseChecks
        def check
          do_check_for_errors_on data, { not_reachable: 'unit queryable' }
          return unless data.is_a?(Hash) && data['ActiveState']

          case @subject.rake_mode
          when 'restart'
            # Long-lived daemon: must be active (covers the "stopped but not
            # failed" case the generic failed-units check misses).
            do_check :rake_not_running, 'daemon running', {
              critical: data['ActiveState'] != 'active'
            }, message: "Unit #{data['ActiveState']}/#{data['SubState']}",
               value: data['ActiveState']
          when 'timer'
            check_last_run
            check_timer_armed
          when 'single'
            check_last_run
          end
        end

        private

        # Flag a non-successful last run. Only meaningful once the task has run
        # at least once (a never-run one-shot reports Result=success by default).
        def check_last_run
          return unless data['ExecMainExitTimestamp'].present?

          do_check :rake_last_run_failed, 'last run succeeded', {
            warning: data['Result'] != 'success'
          }, message: "Last run: #{data['Result']} (exit #{data['exit_status']}) at #{data['ExecMainExitTimestamp']}",
             value: data['Result']
        end

        # A dead/disabled timer is "inactive", not "failed", so nothing else
        # notices when a scheduled task silently stops firing.
        def check_timer_armed
          timer = data['timer'] || {}
          return unless timer['ActiveState']

          do_check :rake_timer_inactive, 'timer armed', {
            warning: timer['ActiveState'] != 'active'
          }, message: "Timer #{timer['ActiveState']}/#{timer['SubState']} — scheduled task not armed",
             value: timer['ActiveState']
        end
      end
    end
  end
end
