module CloudModel
  module Notifiers
    # Abstract base class for monitoring notifiers.
    #
    # Subclasses implement {#send_message} to dispatch alert messages through
    # a specific channel (Slack, log file, email, etc.). Instances are
    # configured via the `monitoring_notifiers` array in {CloudModel::Config}:
    #
    # @example
    #   CloudModel.configure do |c|
    #     c.monitoring_notifiers = [
    #       { severity: [:critical, :fatal],
    #         notifier: CloudModel::Notifiers::SlackNotifier.new(push_url: '...') }
    #     ]
    #   end
    class BaseNotifier
      # @param options [Hash] notifier-specific configuration options
      def initialize options={}
        @options = options
      end

      # Sends a notification message. Subclasses must override this method.
      #
      # @param subject [String] short summary line (shown as the notification title)
      # @param message [String] full message body
      # @return [void]
      def send_message subject, message
      end
    end
  end
end