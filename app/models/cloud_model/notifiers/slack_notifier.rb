require 'net/http'
require 'uri'

module CloudModel
  module Notifiers
    # Posts monitoring notifications to a Slack channel via an incoming webhook.
    #
    # @example
    #   CloudModel::Notifiers::SlackNotifier.new(push_url: 'https://hooks.slack.com/...')
    class SlackNotifier < CloudModel::Notifiers::BaseNotifier
      # Posts the notification to Slack as a Block Kit message.
      # Does nothing if no `:push_url` option was provided.
      #
      # @param subject [String] shown in bold as the first line of the message
      # @param message [String] shown as block-quoted body text
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