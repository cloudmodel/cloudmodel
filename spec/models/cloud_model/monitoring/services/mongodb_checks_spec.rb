# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::MongodbChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Mongodb, guest: guest }
  subject { CloudModel::Monitoring::Services::MongodbChecks.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::Services::BaseChecks }

  describe 'sample_metrics' do
    it 'keeps a handful of gauges from serverStatus instead of flattening all of it' do
      allow(subject).to receive(:data).and_return(
        'connections' => {'current' => 32, 'available' => 800},
        'mem' => {'resident' => 550},
        'globalLock' => {'currentQueue' => {'readers' => 0, 'writers' => 1}, 'activeClients' => {'readers' => 2, 'writers' => 0}},
        'metrics' => {'cursor' => {'open' => {'total' => 3}}, 'document' => {'inserted' => 1_000_000}},
        'wiredTiger' => {'cache' => {'bytes currently in the cache' => 429_496_730, 'maximum bytes configured' => 536_870_912, 'tracked dirty bytes in the cache' => 9_026_846},
                         'transaction' => {'transaction checkpoint most recent time (msecs)' => 7822}},
        'opcounters' => {'query' => 41_605})
      m = subject.sample_metrics
      expect(m).to eq('db.connections' => 32.0, 'db.cursors' => 3.0, 'db.queue_readers' => 0.0, 'db.queue_writers' => 1.0,
                      'db.active_readers' => 2.0, 'db.active_writers' => 0.0, 'db.resident_mb' => 550.0, 'db.checkpoint_ms' => 7822.0,
                      'db.cache_usage' => 80.0, 'db.cache_dirty_mb' => 8.6)
    end

    it 'records nothing for an unreachable service' do
      allow(subject).to receive(:data).and_return(key: :not_reachable)
      expect(subject.sample_metrics).to eq({})
    end
  end

  describe 'check' do
    it 'should check for reachability' do
      test_data = {key: :ok}
      allow(subject).to receive(:data).and_return test_data
      allow(subject).to receive(:do_check_for_errors_on)

      subject.check

      expect(subject).to have_received(:do_check_for_errors_on).with(test_data, {
        not_reachable: 'service reachable'
      })
    end
  end
end