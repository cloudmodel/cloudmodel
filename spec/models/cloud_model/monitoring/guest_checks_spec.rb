# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::GuestChecks do
  let(:host) {double CloudModel::Host, name: 'testhost'}
  let(:guest) { double CloudModel::Guest, host: host}
  subject { CloudModel::Monitoring::GuestChecks.new guest, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe 'indent_size' do
    it 'should indent by 2' do
      expect(subject.indent_size).to eq 2
    end
  end

  describe 'line_prefix' do
    it 'should prefix host name before indention' do
      expect(subject.line_prefix).to eq '[testhost]   '
    end
  end

  describe 'acquire_data' do
    it 'should acquire system and lxc info' do
      expect(guest).to receive(:system_info).and_return 'system info'
      expect(guest).to receive(:lxc_info).and_return 'lxc info'

      expect(subject.acquire_data).to eq system: 'system info', lxc: 'lxc info'
    end
  end

  describe 'check' do
    it 'should call check_system_info on started guest' do
      allow(guest).to receive(:up_state).and_return :started
      issues = []
      allow(guest).to receive(:item_issues).and_return issues
      allow(issues).to receive(:where).with(key: :sys_boot_failed, resolved_at: nil).and_return []

      expect(subject).to receive(:check_system_info).and_return true
      expect(subject.check).to eq true
    end

    it 'should resolve boot issue on started guest' do
      issue = double CloudModel::ItemIssue
      issues = []
      filtered_issues = [issue]

      time_now = Time.now
      allow(Time).to receive(:now).and_return time_now

      allow(guest).to receive(:up_state).and_return :started
      allow(guest).to receive(:item_issues).and_return issues
      allow(issues).to receive(:where).with(key: :sys_boot_failed, resolved_at: nil).and_return filtered_issues
      expect(issue).to receive(:update_attribute).with(:resolved_at, time_now)

      allow(subject).to receive(:check_system_info).and_return true
      expect(subject.check).to eq true
    end

    it 'should check for boot problems on booting guest' do
      allow(guest).to receive(:up_state).and_return :booting
      allow(guest).to receive(:last_downtime_at).and_return nil

      expect do
        expect(subject.check).to eq false
      end.to output("[testhost]     * Not checking (booting)\n").to_stdout
    end

    it 'should alert for boot problems on booting guest if boot is longer than 5 minutes' do
      time_now = Time.now
      allow(Time).to receive(:now).and_return time_now

      allow(guest).to receive(:up_state).and_return :booting
      allow(guest).to receive(:last_downtime_at).and_return time_now - 667
      expect(subject).to receive(:do_check).with(
        :sys_boot_failed,
        "Check boot is not hung up",
        {fatal: true},
        {
          message: "System booting for 11:07",
          value: "11:07"
        }
      ) do
        puts "[testhost]     * Check boot is not hung up"
      end

      expect do
        expect(subject.check).to eq false
      end.to output("[testhost]     * Check boot is not hung up\n").to_stdout
    end

    it 'should format boot alert if it took over an hour' do
      time_now = Time.now
      allow(Time).to receive(:now).and_return time_now

      allow(guest).to receive(:up_state).and_return :booting
      allow(guest).to receive(:last_downtime_at).and_return time_now - 3666
      expect(subject).to receive(:do_check).with(
        :sys_boot_failed,
        "Check boot is not hung up",
        {fatal: true},
        {
          message: "System booting for 1:01:06",
          value: "1:01:06"
        }
      ) do
        puts "[testhost]     * Check boot is not hung up"
      end

      expect do
        expect(subject.check).to eq false
      end.to output("[testhost]     * Check boot is not hung up\n").to_stdout
    end


    it 'should check on not booting/started guest' do
      allow(guest).to receive(:up_state).and_return :not_deployed_yet

      expect do
        expect(subject.check).to eq false
      end.to output("[testhost]     * Not checking (not_deployed_yet)\n").to_stdout
    end
  end
end