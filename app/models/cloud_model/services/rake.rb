module CloudModel
  module Services
    # Scheduled Rake task runner service embedded in a {Guest}.
    #
    # Runs a Rails Rake task on a systemd timer. The timer can be configured
    # to fire at a specific calendar time, after boot, or both. The accuracy
    # window (`rake_timer_accuracy_sec`) controls how much systemd may delay
    # the timer to optimise power usage.
    class Rake < Base
      RAKE_MODES = %w[timer restart single].freeze

      # @!attribute [rw] rake_task
      #   @return [String] the Rake task name to run, e.g. `"my_app:daily_report"`
      field :rake_task, type: String

      # @!attribute [rw] rake_mode
      #   @return [String] execution mode:
      #     `"timer"` — one-shot triggered by a systemd timer (default)
      #     `"restart"` — long-lived daemon with Restart=always
      #     `"single"` — runs once on boot, no timer, no auto-restart
      field :rake_mode, type: String, default: 'timer'

      validates :rake_mode, inclusion: { in: RAKE_MODES }

      # --- Restart/single mode fields ---

      # @!attribute [rw] rake_restart_sec
      #   @return [Integer] systemd `RestartSec` — seconds before restarting
      #     a crashed process (restart mode only, default: 2)
      field :rake_restart_sec, type: Integer, default: 2

      # @!attribute [rw] rake_stop_timeout
      #   @return [Integer] systemd `TimeoutStopSec` — seconds to wait for
      #     graceful shutdown before SIGKILL (default: 30)
      field :rake_stop_timeout, type: Integer, default: 30

      # @!attribute [rw] rake_restart_on_touch
      #   @return [Boolean] install a systemd path unit that restarts the service
      #     whenever `restart.txt` is touched (default: true, restart/single modes)
      field :rake_restart_on_touch, type: Mongoid::Boolean, default: true

      # --- Timer mode fields ---

      # @!attribute [rw] rake_timer_accuracy_sec
      #   @return [Integer] systemd `AccuracySec` in seconds (default: 600)
      field :rake_timer_accuracy_sec, type: Integer, default: 600

      # @!attribute [rw] rake_timer_on_calendar
      #   @return [Boolean] whether to fire on a calendar schedule
      field :rake_timer_on_calendar, type: Mongoid::Boolean, default: true

      # @!attribute [rw] rake_timer_on_calendar_val
      #   @return [String] systemd `OnCalendar` value (default: `"00:00"`, i.e. midnight)
      field :rake_timer_on_calendar_val, type: String, default: '00:00'

      # @!attribute [rw] rake_timer_persistent
      #   @return [Boolean] systemd `Persistent=` — run missed firings on next boot
      field :rake_timer_persistent, type: Mongoid::Boolean, default: false

      # @!attribute [rw] rake_timer_on_boot
      #   @return [Boolean] whether to also fire a fixed delay after boot
      field :rake_timer_on_boot, type: Mongoid::Boolean, default: false

      # @!attribute [rw] rake_timer_on_boot_sec
      #   @return [Integer] seconds after boot before the first run (default: 900)
      field :rake_timer_on_boot_sec, type: Integer, default: 900

      def kind
        :headless
      end

      def components_needed
        ([:nginx] + super).uniq
      end

      # Probe the systemd unit(s) backing this Rake task for monitoring.
      #
      # NB: a *failed* rake unit is already surfaced by the guest-level
      # failed-units check (the check_mk agent ships `systemctl --all`). This
      # probe deliberately adds only what that generic check cannot see:
      # the last run's exit status/timestamp (a one-shot that succeeded is
      # "inactive", indistinguishable from one that never runs) and, in timer
      # mode, whether the timer is still armed (a dead timer is "inactive", not
      # "failed"). Returns a data hash, or an error hash `{key:, error:,
      # severity:}` consumed by {CloudModel::Monitoring::Services::RakeChecks}.
      def service_status
        unit  = "rake-#{rake_task}.service"
        props = %w[
          LoadState ActiveState SubState Result ExecMainStatus
          ExecMainStartTimestamp ExecMainExitTimestamp
          ActiveEnterTimestamp InactiveEnterTimestamp NRestarts
        ]

        success, out = guest.exec "systemctl show #{unit.shellescape} --property=#{props.join(',')} --no-pager"
        unless success
          return { key: :not_reachable, error: "systemctl show #{unit} failed:\n\n#{out}", severity: :critical }
        end

        status = parse_systemctl_show out
        status['exit_status'] = status['ExecMainStatus'].to_i
        status['restarts']    = status['NRestarts'].to_i

        if rake_mode == 'timer'
          tsuccess, tout = guest.exec "systemctl show rake-#{rake_task.shellescape}.timer --property=ActiveState,SubState,LastTriggerUSec,NextElapseUSecRealtime --no-pager"
          status['timer'] = parse_systemctl_show(tout) if tsuccess
        end

        status
      end

      private

      # Parse `systemctl show` KEY=VALUE lines into a hash (blank values kept as
      # empty strings, e.g. `ExecMainExitTimestamp=` when the task never ran).
      def parse_systemctl_show output
        output.to_s.lines.each_with_object({}) do |line, h|
          k, v = line.strip.split('=', 2)
          h[k] = v.to_s if k
        end
      end
    end
  end
end