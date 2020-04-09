# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Notifiers::BaseNotifier do
  describe 'initialize' do
    it 'should take and store options' do
      options = double
      
      notifier = CloudModel::Notifiers::BaseNotifier.new options
      
      expect(notifier.instance_variable_get :@options).to eq options
    end
  end
  
  describe 'send_message' do
    it 'should accept 2 params and do nothing' do
      expect(subject.send_message 'subject', 'message').to eq nil
    end
  end
end