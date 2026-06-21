# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::FusekiChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Fuseki, guest: guest }
  subject { CloudModel::Monitoring::Services::FusekiChecks.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::Services::BaseChecks }

  describe 'check' do
    it 'should check for fuseki specific errors' do
      test_data = {key: :ok}
      allow(subject).to receive(:data).and_return test_data
      allow(subject).to receive(:do_check_for_errors_on)

      subject.check

      expect(subject).to have_received(:do_check_for_errors_on).with(test_data, {
        not_reachable: 'service reachable',
        no_fuseki_status: 'status available',
        fuseki_status_forbidden: 'status forbidden',
        parse_result: 'parse status'
      })
    end
  end
end