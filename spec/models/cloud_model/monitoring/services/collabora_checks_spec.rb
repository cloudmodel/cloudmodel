# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::CollaboraChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Collabora, guest: guest }
  subject { described_class.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::Services::BaseChecks }

  describe 'check' do
    it 'checks reachability, WOPI discovery and the conversion engine' do
      test_data = { 'code' => 200, 'discovery_ok' => true, 'convert_to' => 1 }
      allow(subject).to receive(:data).and_return test_data
      allow(subject).to receive(:do_check_for_errors_on)
      allow(subject).to receive(:do_check)

      subject.check

      expect(subject).to have_received(:do_check_for_errors_on).with(test_data, {
        not_reachable: 'service reachable',
        no_discovery:  'WOPI discovery available'
      })
      expect(subject).to have_received(:do_check).with(
        :collabora_convert_to, 'document conversion available', { warning: false }, hash_including(:message)
      )
    end

    it 'warns when the conversion engine is unavailable' do
      allow(subject).to receive(:data).and_return({ 'convert_to' => 0 })
      allow(subject).to receive(:do_check_for_errors_on)
      allow(subject).to receive(:do_check)

      subject.check

      expect(subject).to have_received(:do_check).with(
        :collabora_convert_to, anything, { warning: true }, anything
      )
    end

    it 'skips the convert-to check when capabilities are absent' do
      allow(subject).to receive(:data).and_return({ key: :not_reachable })
      allow(subject).to receive(:do_check_for_errors_on)
      allow(subject).to receive(:do_check)

      subject.check

      expect(subject).not_to have_received(:do_check)
    end
  end
end
