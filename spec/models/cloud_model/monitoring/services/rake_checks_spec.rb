# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::RakeChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Rake, guest: guest, rake_mode: 'timer' }
  subject { described_class.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::Services::BaseChecks }

  before do
    allow(subject).to receive(:do_check_for_errors_on)
    allow(subject).to receive(:do_check)
  end

  describe 'check (restart mode)' do
    let(:service) { double CloudModel::Services::Rake, guest: guest, rake_mode: 'restart' }

    it 'is critical when the daemon is not active' do
      allow(subject).to receive(:data).and_return({ 'ActiveState' => 'failed', 'SubState' => 'failed' })

      subject.check

      expect(subject).to have_received(:do_check).with(
        :rake_not_running, anything, { critical: true }, hash_including(:message, :value)
      )
    end

    it 'is ok when the daemon is active' do
      allow(subject).to receive(:data).and_return({ 'ActiveState' => 'active', 'SubState' => 'running' })

      subject.check

      expect(subject).to have_received(:do_check).with(
        :rake_not_running, anything, { critical: false }, anything
      )
    end
  end

  describe 'check (timer mode)' do
    let(:service) { double CloudModel::Services::Rake, guest: guest, rake_mode: 'timer' }

    it 'warns on a failed last run and a stalled timer' do
      allow(subject).to receive(:data).and_return({
        'ActiveState' => 'inactive', 'SubState' => 'dead',
        'Result' => 'exit-code', 'exit_status' => 1,
        'ExecMainExitTimestamp' => 'Thu 2026-07-17 00:00:03 CEST',
        'timer' => { 'ActiveState' => 'inactive', 'SubState' => 'dead' }
      })

      subject.check

      expect(subject).to have_received(:do_check).with(
        :rake_last_run_failed, anything, { warning: true }, hash_including(:message, :value)
      )
      expect(subject).to have_received(:do_check).with(
        :rake_timer_inactive, anything, { warning: true }, hash_including(:message, :value)
      )
    end

    it 'is ok on a successful run with an armed timer' do
      allow(subject).to receive(:data).and_return({
        'ActiveState' => 'inactive', 'SubState' => 'dead',
        'Result' => 'success', 'exit_status' => 0,
        'ExecMainExitTimestamp' => 'Thu 2026-07-17 00:00:03 CEST',
        'timer' => { 'ActiveState' => 'active', 'SubState' => 'waiting' }
      })

      subject.check

      expect(subject).to have_received(:do_check).with(:rake_last_run_failed, anything, { warning: false }, anything)
      expect(subject).to have_received(:do_check).with(:rake_timer_inactive, anything, { warning: false }, anything)
    end

    it 'does not check the last run before the task has ever run' do
      allow(subject).to receive(:data).and_return({
        'ActiveState' => 'inactive', 'SubState' => 'dead',
        'Result' => 'success', 'ExecMainExitTimestamp' => '',
        'timer' => { 'ActiveState' => 'active', 'SubState' => 'waiting' }
      })

      subject.check

      expect(subject).not_to have_received(:do_check).with(:rake_last_run_failed, anything, anything, anything)
    end
  end

  describe 'check (unreachable)' do
    let(:service) { double CloudModel::Services::Rake, guest: guest, rake_mode: 'timer' }

    it 'runs no state checks when the unit could not be queried' do
      allow(subject).to receive(:data).and_return({ key: :not_reachable })

      subject.check

      expect(subject).not_to have_received(:do_check)
    end
  end
end
