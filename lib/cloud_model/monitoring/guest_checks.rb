module CloudModel
  module Monitoring
    class GuestChecks < CloudModel::Monitoring::BaseChecks
      require_relative "mixins/sysinfo_checks_mixin" unless Rails.env.development?
      include CloudModel::Monitoring::Mixins::SysinfoChecksMixin

      def indent_size
        2
      end

      def line_prefix
        "[#{@subject.host.name}] #{super}"
      end

      def acquire_data
        {
          system: @subject.system_info,
          lxc: @subject.lxc_info
        }
      end

      def check
        case @subject.up_state
        when :started
          # Resolve boot issue once the guest is running
          if issue = @subject.item_issues.where(key: :sys_boot_failed, resolved_at: nil).first
            issue.update_attribute :resolved_at, Time.now
          end
          check_system_info
        when :booting
          if @subject.last_downtime_at and @subject.last_downtime_at < Time.now - 5.minutes
            delay_time = (Time.now - @subject.last_downtime_at).to_i
            if delay_time > 3600
              delay_string = "#{delay_time / 3600}:#{"%02d" % ((delay_time / 60) % 60)}:#{"%02d" % (delay_time % 60)}"
            else
              delay_string = "#{delay_time / 60}:#{"%02d" % (delay_time % 60)}"
            end

            do_check :sys_boot_failed, 'Check boot is not hung up', {fatal: true}, message: "System booting for #{delay_string}", value: delay_string
          else
            puts "#{line_prefix}  * Not checking (#{@subject.up_state})"
          end

          false
        else
          puts "#{line_prefix}  * Not checking (#{@subject.up_state})"
          false
        end
      end
    end
  end
end