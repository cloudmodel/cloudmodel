module CloudModel
  module Services
    # Scheduled Rake task runner service embedded in a {Guest}.
    #
    # Runs a Rails Rake task on a systemd timer. The timer can be configured
    # to fire at a specific calendar time, after boot, or both. The accuracy
    # window (`rake_timer_accuracy_sec`) controls how much systemd may delay
    # the timer to optimise power usage.
    class Rake < Base
      # @!attribute [rw] rake_task
      #   @return [String] the Rake task name to run, e.g. `"my_app:daily_report"`
      field :rake_task, type: String

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

      def service_status
        false
      end
    end
  end
end