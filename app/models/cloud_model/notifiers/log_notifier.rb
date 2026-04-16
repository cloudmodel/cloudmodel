module CloudModel
  module Notifiers
    # Writes monitoring notifications to a log file.
    #
    # @example
    #   CloudModel::Notifiers::LogNotifier.new(path: '/var/log/cloudmodel-alerts.log')
    class LogNotifier < CloudModel::Notifiers::BaseNotifier
      # Appends the notification to the configured log file.
      # Does nothing if no `:path` option was provided.
      #
      # @param subject [String] notification subject line
      # @param message [String] notification body
      def send_message subject, message
        if @options[:path]
          File.open(@options[:path], 'a') do |f|
            f << "#{Time.now}\n*#{subject}\n#{message.lines.map{|l| "| #{l}"} * ""}\n\n"
          end
        end
      end
    end
  end
end