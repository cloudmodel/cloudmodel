module CloudModel
  module Services
    class Rake < Base
      field :rake_task, type: String
      field :rake_timer_accuracy_sec, type: Integer, default: 600
      field :rake_timer_on_calendar, type: Mongoid::Boolean, default: true
      field :rake_timer_on_calendar_val, type: String, default: '00:00'
      field :rake_timer_persistent, type: Mongoid::Boolean, default: false
      field :rake_timer_on_boot, type: Mongoid::Boolean, default: false
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