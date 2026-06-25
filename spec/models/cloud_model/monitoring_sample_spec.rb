# encoding: UTF-8

require 'spec_helper'

describe CloudModel::MonitoringSample do
  it { expect(subject).to have_field(:resolution).of_type(String).with_default_value_of('raw') }
  it { expect(subject).to have_field(:ref_at).of_type(Time) }
  it { expect(subject).to have_field(:metrics).of_type(Hash).with_default_value_of({}) }
  it { expect(subject).to have_field(:expires_at).of_type(Time) }
  it { expect(subject).to belong_to(:subject) }

  describe 'indexes' do
    let(:keys) { CloudModel::MonitoringSample.index_specifications.map(&:key) }

    it 'should index by subject, resolution and time' do
      expect(keys).to include(subject_type: 1, subject_id: 1, resolution: 1, ref_at: 1)
    end

    it 'should have a TTL index on expires_at' do
      ttl = CloudModel::MonitoringSample.index_specifications.find { |s| s.key == {expires_at: 1} }
      expect(ttl).not_to be_nil
      expect(ttl.options[:expire_after]).to eq 0
    end
  end

  describe 'self.retention_for' do
    it 'should read the configured retention window per resolution' do
      expect(CloudModel::MonitoringSample.retention_for('raw')).to eq CloudModel.config.monitoring_sample_retention[:raw]
      expect(CloudModel::MonitoringSample.retention_for('day')).to eq CloudModel.config.monitoring_sample_retention[:day]
    end
  end

  describe 'self.bucket_time' do
    it 'should floor a timestamp to the start of its bucket' do
      t = Time.utc(2026, 1, 1, 12, 24, 17)
      expect(CloudModel::MonitoringSample.bucket_time(t, 1.hour)).to eq Time.utc(2026, 1, 1, 12)
      expect(CloudModel::MonitoringSample.bucket_time(t, 1.day)).to eq Time.utc(2026, 1, 1)
    end
  end

  describe 'self.average_metrics' do
    it 'should average each metric across the given hashes' do
      result = CloudModel::MonitoringSample.average_metrics [
        {'a' => 2.0, 'b' => 4.0},
        {'a' => 4.0}
      ]
      expect(result).to eq 'a' => 3.0, 'b' => 4.0
    end

    it 'should ignore non-numeric values' do
      result = CloudModel::MonitoringSample.average_metrics [{'a' => 2.0, 'b' => 'nope'}]
      expect(result).to eq 'a' => 2.0
    end

    it 'should return an empty hash for no input' do
      expect(CloudModel::MonitoringSample.average_metrics([])).to eq({})
    end
  end

  describe 'self.record!' do
    let(:check_subject) { Factory :certificate }

    it 'should create a raw sample with TTL based expiry' do
      Timecop.freeze(Time.utc(2026, 6, 25, 10, 0, 0)) do
        sample = CloudModel::MonitoringSample.record! check_subject, {'cpu.load_1' => 1.5}, at: Time.now

        expect(sample).to be_persisted
        expect(sample.resolution).to eq 'raw'
        expect(sample.subject).to eq check_subject
        expect(sample.ref_at).to eq Time.now
        expect(sample.metrics).to eq 'cpu.load_1' => 1.5
        expect(sample.expires_at).to eq Time.now + CloudModel.config.monitoring_sample_retention[:raw]
      end
    end

    it 'should reject nil-valued metrics' do
      sample = CloudModel::MonitoringSample.record! check_subject, {'a' => 1.0, 'b' => nil}
      expect(sample.metrics).to eq 'a' => 1.0
    end

    it 'should not create a sample when there are no metrics' do
      expect(CloudModel::MonitoringSample.record!(check_subject, {})).to be_nil
      expect(CloudModel::MonitoringSample.record!(check_subject, nil)).to be_nil
      expect(CloudModel::MonitoringSample.record!(check_subject, {'a' => nil})).to be_nil
    end
  end

  describe 'self.rollup_resolution!' do
    let(:subject_id) { BSON::ObjectId.new }

    def raw_sample(ref_at, metrics)
      CloudModel::MonitoringSample.create!(
        subject_type: 'CloudModel::Host', subject_id: subject_id,
        resolution: 'raw', ref_at: ref_at, metrics: metrics, expires_at: ref_at + 2.days
      )
    end

    it 'should average the finer samples into one bucket' do
      Timecop.freeze(Time.utc(2026, 6, 25, 12, 30, 0)) do
        raw_sample Time.utc(2026, 6, 25, 12, 6), {'cpu.load_1' => 2.0, 'mem.usage' => 50.0}
        raw_sample Time.utc(2026, 6, 25, 12, 9), {'cpu.load_1' => 4.0, 'mem.usage' => 60.0}

        CloudModel::MonitoringSample.rollup_resolution! 'raw', 'hour', recompute: 2.hours

        hours = CloudModel::MonitoringSample.where(subject_id: subject_id, resolution: 'hour').to_a
        expect(hours.size).to eq 1
        expect(hours.first.ref_at).to eq Time.utc(2026, 6, 25, 12)
        expect(hours.first.metrics).to eq 'cpu.load_1' => 3.0, 'mem.usage' => 55.0
        expect(hours.first.expires_at).to eq Time.utc(2026, 6, 25, 12) + CloudModel.config.monitoring_sample_retention[:hour]
      end
    end

    it 'should be idempotent across repeated runs (upsert)' do
      Timecop.freeze(Time.utc(2026, 6, 25, 12, 30, 0)) do
        raw_sample Time.utc(2026, 6, 25, 12, 6), {'cpu.load_1' => 2.0}
        raw_sample Time.utc(2026, 6, 25, 12, 9), {'cpu.load_1' => 4.0}

        2.times { CloudModel::MonitoringSample.rollup_resolution! 'raw', 'hour', recompute: 2.hours }

        expect(CloudModel::MonitoringSample.where(subject_id: subject_id, resolution: 'hour').count).to eq 1
      end
    end

    it 'should ignore samples older than the recompute window' do
      Timecop.freeze(Time.utc(2026, 6, 25, 12, 30, 0)) do
        raw_sample Time.utc(2026, 6, 25, 9, 0), {'cpu.load_1' => 9.0} # 3.5h ago

        CloudModel::MonitoringSample.rollup_resolution! 'raw', 'hour', recompute: 2.hours

        expect(CloudModel::MonitoringSample.where(subject_id: subject_id, resolution: 'hour').count).to eq 0
      end
    end
  end

  describe 'self.rollup!' do
    it 'should roll up raw into hour and hour into day' do
      expect(CloudModel::MonitoringSample).to receive(:rollup_resolution!).with('raw', 'hour', recompute: 2.hours)
      expect(CloudModel::MonitoringSample).to receive(:rollup_resolution!).with('hour', 'day', recompute: 2.days)

      CloudModel::MonitoringSample.rollup!
    end
  end
end
