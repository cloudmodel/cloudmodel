# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::ForgejoChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Forgejo, guest: guest }
  subject { CloudModel::Monitoring::Services::ForgejoChecks.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::Services::BaseChecks }

  describe 'check' do
    it 'should check for forgejo specific errors' do
      test_data = {key: :ok}
      allow(subject).to receive(:data).and_return test_data
      allow(subject).to receive(:do_check_for_errors_on)

      subject.check

      expect(subject).to have_received(:do_check_for_errors_on).with(test_data, {
        not_reachable: 'service reachable',
        not_found: 'metrics available',
        not_parsable: 'parse metrics'
      })
    end
  end
end
