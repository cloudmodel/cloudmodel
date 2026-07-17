# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Rake do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject.allow_public_service?).to eq false }

  it { expect(subject).to have_field(:rake_task).of_type String }
  it { expect(subject).to have_field(:rake_timer_accuracy_sec).of_type(Integer).with_default_value_of 600 }
  it { expect(subject).to have_field(:rake_timer_on_calendar).of_type(Mongoid::Boolean).with_default_value_of true }
  it { expect(subject).to have_field(:rake_timer_on_calendar_val).of_type(String).with_default_value_of '00:00' }
  it { expect(subject).to have_field(:rake_timer_persistent).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:rake_timer_on_boot).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:rake_timer_on_boot_sec).of_type(Integer).with_default_value_of 900 }

  describe 'kind' do
    it 'should return :headless' do
      expect(subject.kind).to eq :headless
    end
  end

  describe 'components_needed' do
    it 'should require nginx component' do
      expect(subject.components_needed).to eq [:nginx]
    end
  end

  describe 'service_status' do
    let(:guest) { double CloudModel::Guest }
    before do
      allow(subject).to receive(:guest).and_return guest
      subject.rake_task = 'my_app:sync'
    end

    it 'parses systemctl show output for the service unit' do
      subject.rake_mode = 'restart'
      allow(guest).to receive(:exec).and_return([true,
        "ActiveState=active\nSubState=running\nResult=success\nExecMainStatus=0\nNRestarts=2\nExecMainExitTimestamp=\n"])

      status = subject.service_status
      expect(status['ActiveState']).to eq 'active'
      expect(status['exit_status']).to eq 0
      expect(status['restarts']).to eq 2
    end

    it 'also queries the timer unit in timer mode' do
      subject.rake_mode = 'timer'
      allow(guest).to receive(:exec) do |cmd|
        if cmd.include?('.timer')
          [true, "ActiveState=active\nSubState=waiting\n"]
        else
          [true, "ActiveState=inactive\nSubState=dead\nResult=success\nExecMainStatus=0\n"]
        end
      end

      expect(subject.service_status['timer']).to eq('ActiveState' => 'active', 'SubState' => 'waiting')
    end

    it 'returns a critical not_reachable error when systemctl fails' do
      subject.rake_mode = 'restart'
      allow(guest).to receive(:exec).and_return([false, 'boom'])

      result = subject.service_status
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :critical
    end
  end
end