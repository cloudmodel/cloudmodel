require 'spec_helper'

describe CloudModel::Mixins::Backupable do
  subject { CloudModel::MongodbReplicationSet.create! name: "backupable-spec-#{SecureRandom.hex 4}" }

  after { subject.delete }

  describe 'update_backup_state' do
    it 'persists state and timestamp atomically' do
      subject.update_backup_state 'running'

      subject.reload
      expect(subject.backup_state).to eq 'running'
      expect(subject.backup_state_at).to be_within(5.seconds).of Time.now
    end

    it 'never raises on bookkeeping errors' do
      allow(subject).to receive(:set).and_raise('db gone')

      expect { subject.update_backup_state 'running' }.not_to raise_error
    end
  end

  describe 'backup_with_state' do
    it 'records success' do
      expect(subject).to receive(:backup).and_return(true)

      expect(subject.backup_with_state).to eq true
      expect(subject.reload.backup_state).to eq 'success'
    end

    it 'records failure on a falsey backup' do
      expect(subject).to receive(:backup).and_return(false)

      expect(subject.backup_with_state).to eq false
      expect(subject.reload.backup_state).to eq 'failed'
    end

    it 'records failure and re-raises on an exception' do
      expect(subject).to receive(:backup).and_raise('boom')

      expect { subject.backup_with_state }.to raise_error 'boom'
      expect(subject.reload.backup_state).to eq 'failed'
    end
  end

  describe 'backup_active?' do
    it 'is true for fresh queued and running states' do
      %w(queued running).each do |state|
        subject.update_backup_state state
        expect(subject.backup_active?).to eq true
      end
    end

    it 'is false for finished states and stale markers' do
      subject.update_backup_state 'success'
      expect(subject.backup_active?).to eq false

      subject.update_backup_state 'running'
      subject.set backup_state_at: 2.days.ago
      expect(subject.backup_active?).to eq false
    end
  end
end
