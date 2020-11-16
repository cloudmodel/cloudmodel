# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Notifiers::LogNotifier do
  it { expect(subject).to be_a CloudModel::Notifiers::BaseNotifier }

  describe 'send_message' do
    it 'should append to path' do
      subject.instance_variable_set :@options, {path: '/var/log/notifications.md'}

      time_now = Time.now
      allow(Time).to receive(:now).and_return time_now

      file = double File

      expect(File).to receive(:open).with('/var/log/notifications.md', 'a').and_yield file
      expect(file).to receive(:<<).with("#{time_now}\n*Some Subject\n| Some Message\n| Multiline\n\n").and_return true

      expect(subject.send_message 'Some Subject', "Some Message\nMultiline").to eq true
    end

    it 'should do nothing of path is blank' do
      expect(File).not_to receive(:open)
      expect(subject.send_message 'Some Subject', 'Some Message').to eq nil
    end
  end
end