module CloudModel
  module Notifiers
    class LogNotifier < CloudModel::Notifiers::BaseNotifier
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