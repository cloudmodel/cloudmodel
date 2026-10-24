# encoding: UTF-8

require 'spec_helper'

describe CloudModel::MonitoringHeartbeat do
  let(:now) { Time.at(1_700_000_000) }

  before do
    allow(CloudModel::MonitoringHeartbeat).to receive(:own_host_name).and_return 'adm-a'
  end

  it { expect(subject).to have_timestamps }
  it { expect(subject).to have_field(:host_name).of_type String }
  it { expect(subject).to have_field(:started_at).of_type Time }
  it { expect(subject).to have_field(:finished_at).of_type Time }
  it { expect(subject).to have_field(:duration).of_type Float }

  describe 'start! and beat!' do
    it 'should keep one record per host' do
      CloudModel::MonitoringHeartbeat.start! started_at: now
      CloudModel::MonitoringHeartbeat.beat! started_at: now
      CloudModel::MonitoringHeartbeat.start! started_at: now + 700

      expect(CloudModel::MonitoringHeartbeat.count).to eq 1
      heartbeat = CloudModel::MonitoringHeartbeat.first
      expect(heartbeat.host_name).to eq 'adm-a'
      expect(heartbeat.started_at).to eq now + 700
      expect(heartbeat.finished_at).not_to be_nil
      expect(heartbeat.duration).to be > 0
    end

    it 'should swallow database errors' do
      allow(CloudModel::MonitoringHeartbeat).to receive(:find_or_initialize_by).and_raise 'db gone'

      expect { CloudModel::MonitoringHeartbeat.beat! started_at: now }.not_to raise_error
    end
  end

  describe 'stale' do
    it 'should list other hosts whose last cycle is older than max_age or missing' do
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-a', finished_at: now - 5.hours
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-b', finished_at: now - 5.hours
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-c', finished_at: now - 10.minutes
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-d', started_at: now - 4.hours

      expect(CloudModel::MonitoringHeartbeat.stale(now: now).map(&:host_name)).to match_array %w(adm-b adm-d)
    end

    it 'should ignore hosts not seen for a week' do
      old = CloudModel::MonitoringHeartbeat.create! host_name: 'adm-b', finished_at: now - 10.days
      old.set updated_at: now - 10.days

      expect(CloudModel::MonitoringHeartbeat.stale(now: now)).to eq []
    end
  end

  describe 'stagger_delay' do
    it 'should be zero without another host' do
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-a', started_at: now - 100, finished_at: now - 10, duration: 90

      expect(CloudModel::MonitoringHeartbeat.stagger_delay(pause: 180, now: now)).to eq 0
    end

    it 'should wait for the middle of the other host\'s period' do
      # period = 420 s + 180 s = 600 s; peer started 60 s ago → middle in 240 s
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-b', started_at: now - 60, finished_at: now - 60, duration: 420

      expect(CloudModel::MonitoringHeartbeat.stagger_delay(pause: 180, now: now)).to eq 240
    end

    it 'should take the longest cycle of all hosts as the period' do
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-a', started_at: now - 1000, finished_at: now - 200, duration: 820
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-b', started_at: now - 100, finished_at: now - 700, duration: 420

      # period 1000 s, peer phase 100 s → middle in 400 s
      expect(CloudModel::MonitoringHeartbeat.stagger_delay(pause: 180, now: now)).to eq 400
    end

    it 'should not wait once past the middle' do
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-b', started_at: now - 310, duration: 420

      expect(CloudModel::MonitoringHeartbeat.stagger_delay(pause: 180, now: now)).to eq 0
    end

    it 'should not wait when exactly in place' do
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-b', started_at: now - 300, duration: 420

      expect(CloudModel::MonitoringHeartbeat.stagger_delay(pause: 180, now: now)).to eq 0
    end

    it 'should ignore a host that stopped cycling' do
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-b', started_at: now - 2.hours, finished_at: now - 2.hours, duration: 420

      expect(CloudModel::MonitoringHeartbeat.stagger_delay(pause: 180, now: now)).to eq 0
    end

    it 'should assume a default duration before any cycle completed' do
      CloudModel::MonitoringHeartbeat.create! host_name: 'adm-b', started_at: now - 30

      # period 600 + 180 = 780 → middle in 360
      expect(CloudModel::MonitoringHeartbeat.stagger_delay(pause: 180, now: now)).to eq 360
    end
  end
end
