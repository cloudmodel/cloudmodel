require 'spec_helper'

describe CloudModel::Monitoring do
  it 'should have registered checks' do
    checks = CloudModel::Monitoring.instance_variable_get(:@checks)
    expect(checks).to be_a Array
  end

  describe '.check' do
    # A registered check group is just an object that responds to .check.
    let(:boom)  { double('BoomChecks', name: 'CloudModel::Monitoring::BoomChecks') }
    let(:clean) { double('CleanChecks', name: 'CloudModel::Monitoring::CleanChecks') }

    before do
      @saved_checks = CloudModel::Monitoring.instance_variable_get(:@checks)
      CloudModel::Monitoring.instance_variable_set(:@checks, [boom, clean])
    end

    after do
      CloudModel::Monitoring.instance_variable_set(:@checks, @saved_checks)
    end

    it 'does not raise when a check group fails, and still runs the others' do
      allow(boom).to receive(:check).and_raise('driver unreachable')
      allow(clean).to receive(:check)

      expect { CloudModel::Monitoring.check }.not_to raise_error
      expect(clean).to have_received(:check)
    end

    it 'tracks a failing group as an open, keyed ItemIssue' do
      allow(boom).to receive(:check).and_raise('driver unreachable')
      allow(clean).to receive(:check)

      CloudModel::Monitoring.check

      issue = CloudModel::ItemIssue.open.where(key: 'check_crashed_boom_checks').first
      expect(issue).to be_present
      expect(issue.value).to eq 'driver unreachable'
    end

    it 'auto-resolves the issue once the group runs cleanly again' do
      allow(clean).to receive(:check)

      allow(boom).to receive(:check).and_raise('driver unreachable')
      CloudModel::Monitoring.check
      expect(CloudModel::ItemIssue.open.where(key: 'check_crashed_boom_checks').count).to eq 1

      allow(boom).to receive(:check) # recovered
      CloudModel::Monitoring.check
      expect(CloudModel::ItemIssue.open.where(key: 'check_crashed_boom_checks').count).to eq 0
    end
  end
end