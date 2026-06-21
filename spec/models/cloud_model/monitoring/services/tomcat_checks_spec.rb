# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::TomcatChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Tomcat, guest: guest }
  subject { CloudModel::Monitoring::Services::TomcatChecks.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::Services::BaseChecks }

  describe 'check' do
    it 'should check for tomcat specific errors and resource usage' do
      test_data = {key: :ok, 'memory_usage' => 50, 'thread_usage' => 30}
      allow(subject).to receive(:data).and_return test_data
      allow(subject).to receive(:do_check_for_errors_on)
      allow(subject).to receive(:do_check_value)

      subject.check

      expect(subject).to have_received(:do_check_for_errors_on).with(test_data, {
        not_reachable: 'service reachable',
        no_tomcat_status: 'status available',
        tomcat_status_forbidden: 'status forbidden',
        parse_result: 'parse status'
      })

      expect(subject).to have_received(:do_check_value).with(:mem_usage, 50, {
        critical: 90,
        warning: 80
      })

      expect(subject).to have_received(:do_check_value).with(:thread_usage, 30, {
        critical: 90,
        warning: 80
      })
    end
  end
end