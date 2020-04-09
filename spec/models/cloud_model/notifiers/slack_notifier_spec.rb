# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Notifiers::SlackNotifier do
  it { expect(subject).to be_a CloudModel::Notifiers::BaseNotifier }
   
  describe 'send_message' do
    it 'should send https request to push url' do
      subject.instance_variable_set :@options, {push_url: 'https://hooks.slack.com/services/ABC/DEF/1233cc2'}
      
      http = double Net::HTTP
      request = double Net::HTTP::Post
      
      expect(Net::HTTP).to receive(:new).with('hooks.slack.com', 443).and_return http
      expect(http).to receive(:use_ssl=).with(true)
      expect(Net::HTTP::Post).to receive(:new).with('/services/ABC/DEF/1233cc2', {'Content-Type': 'application/json'}).and_return request
      expect(request).to receive(:body=).with("{\"text\":\"Some Subject\"}")
      expect(http).to receive(:request).with(request).and_return '200 OK'
      
      expect(subject.send_message 'Some Subject', 'Some Message').to eq '200 OK'
    end
    
    it 'should do nothing of push url is blank' do
      expect(Net::HTTP).not_to receive(:new)
      expect(subject.send_message 'Some Subject', 'Some Message').to eq nil
    end
  end
end