# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::JitsiChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Jitsi, guest: guest, videobridge_port: 9090 }
  subject { described_class.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::Services::BaseChecks }

  describe 'check' do
    before do
      allow(subject).to receive(:do_check_for_errors_on)
      allow(subject).to receive(:do_check)
    end

    it 'checks Jicofo reachability, stats availability and parsability' do
      allow(subject).to receive(:data).and_return({ 'operational_bridges' => 1, 'bridge_count' => 1, 'videobridge_up' => 1 })

      subject.check

      expect(subject).to have_received(:do_check_for_errors_on).with(anything, {
        not_reachable:   'Jicofo reachable',
        no_jicofo_stats: 'Jicofo stats available',
        parse_result:    'Jicofo stats parsable'
      })
    end

    it 'raises critical when no video bridge is operational' do
      allow(subject).to receive(:data).and_return({ 'operational_bridges' => 0, 'bridge_count' => 1, 'videobridge_up' => 1 })

      subject.check

      expect(subject).to have_received(:do_check).with(
        :jitsi_no_bridge, anything, { critical: true }, hash_including(:message, :value)
      )
      expect(subject).to have_received(:do_check).with(
        :jitsi_videobridge_down, anything, { warning: false }, hash_including(:message, :value)
      )
    end

    it 'is ok when a bridge is operational and warns on a dead videobridge port' do
      allow(subject).to receive(:data).and_return({ 'operational_bridges' => 2, 'bridge_count' => 2, 'videobridge_up' => 0 })

      subject.check

      expect(subject).to have_received(:do_check).with(
        :jitsi_no_bridge, anything, { critical: false }, anything
      )
      expect(subject).to have_received(:do_check).with(
        :jitsi_videobridge_down, anything, { warning: true }, anything
      )
    end

    it 'skips bridge checks when Jicofo was unreachable' do
      allow(subject).to receive(:data).and_return({ key: :not_reachable })

      subject.check

      expect(subject).not_to have_received(:do_check)
    end
  end
end
