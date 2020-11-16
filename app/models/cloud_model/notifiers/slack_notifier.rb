require 'net/http'
require 'uri'

module CloudModel
  module Notifiers
    class SlackNotifier < CloudModel::Notifiers::BaseNotifier
      def send_message subject, message
        if @options[:push_url]
          uri = URI.parse(@options[:push_url])
          message_data = {
            #text: "-> *#{subject}*\n#{message}"
            blocks: [
          		{
          			type: "section",
          			text: {
          				type: "mrkdwn",
          				text: "*#{subject}*\n#{message.lines.map{|l| "> #{l}"} * ""}"
          			}
          		}
          	]
          }

          header = {'Content-Type': 'application/json'}

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          request = Net::HTTP::Post.new(uri.request_uri, header)
          request.body = message_data.to_json.gsub("\\u003e", '>')

          response = http.request(request)
        end
      end
    end
  end
end