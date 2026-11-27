# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::MysqlChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Mysql, guest: guest }
  subject { CloudModel::Monitoring::Services::MysqlChecks.new service, skip_header: true }

  it 'should check for reachability' do
    test_data = {alive: true}
    allow(subject).to receive(:data).and_return test_data
    allow(subject).to receive(:do_check_for_errors_on)
    subject.check
    expect(subject).to have_received(:do_check_for_errors_on).with(test_data, { not_reachable: 'service reachable' })
  end
end
