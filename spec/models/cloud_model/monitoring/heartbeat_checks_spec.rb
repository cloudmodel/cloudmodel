# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::HeartbeatChecks do
  before do
    allow(CloudModel::MonitoringHeartbeat).to receive(:own_host_name).and_return 'adm-a'
    allow(CloudModel.config).to receive(:monitoring_notifiers).and_return []
  end

  it 'should open a critical issue for a stalled host and resolve it when it cycles again' do
    peer = CloudModel::MonitoringHeartbeat.create! host_name: 'adm-b', started_at: 5.hours.ago, finished_at: 5.hours.ago, duration: 500

    expect { CloudModel::Monitoring::HeartbeatChecks.check }.to output(/adm-b has not completed a cycle for 5.0 h/).to_stdout
    issue = CloudModel::ItemIssue.open.find_by key: 'monitoring_stale_adm-b'
    expect(issue.severity).to eq :critical
    expect(issue.subject).to be_nil
    expect(issue.value).to eq '5.0 h'

    peer.update! finished_at: 1.minute.ago
    expect { CloudModel::Monitoring::HeartbeatChecks.check }.to output(/adm-b completed a cycle 1 min ago/).to_stdout
    expect(issue.reload.resolved_at).not_to be_nil
  end

  it 'should flag a host that never completed a cycle' do
    CloudModel::MonitoringHeartbeat.create! host_name: 'adm-b', started_at: 4.hours.ago

    expect { CloudModel::Monitoring::HeartbeatChecks.check }.to output(/adm-b has not completed a cycle for ever/).to_stdout
    expect(CloudModel::ItemIssue.open.find_by(key: 'monitoring_stale_adm-b').value).to eq 'never'
  end

  it 'should not watch itself' do
    CloudModel::MonitoringHeartbeat.create! host_name: 'adm-a', finished_at: 5.hours.ago

    expect { CloudModel::Monitoring::HeartbeatChecks.check }.not_to output.to_stdout
    expect(CloudModel::ItemIssue.open.count).to eq 0
  end
end
