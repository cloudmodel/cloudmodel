require 'spec_helper'

describe CloudModel::BackupJob do
  subject { described_class.new }

  let(:set) { CloudModel::MongodbReplicationSet.create! name: "backup-job-spec-#{SecureRandom.hex 4}" }

  after { set.delete }

  before do
    # Don't touch the real machine-wide lock file in specs.
    allow(CloudModel::BackupRun).to receive(:with_file_lock) { |&block| block.call }
  end

  describe 'perform' do
    it 'backs up the subject inside a tracked one-subject run' do
      expect_any_instance_of(CloudModel::MongodbReplicationSet).to receive(:backup_with_state).and_return(true)

      subject.perform 'replication_set', set.id.to_s

      run = CloudModel::BackupRun.latest
      expect(run.total_subjects).to eq 1
      expect(run.finished_subjects).to eq 1
      expect(run.success).to eq true
      expect(run.active?).to eq false
    end

    it 'marks the run failed without raising when the backup fails' do
      expect_any_instance_of(CloudModel::MongodbReplicationSet).to receive(:backup_with_state).and_return(false)

      expect { subject.perform 'replication_set', set.id.to_s }.not_to raise_error
      expect(CloudModel::BackupRun.latest.success).to eq false
    end

    it 'marks the run failed without raising on an exception' do
      expect_any_instance_of(CloudModel::MongodbReplicationSet).to receive(:backup_with_state).and_raise('boom')

      expect { subject.perform 'replication_set', set.id.to_s }.not_to raise_error
      expect(CloudModel::BackupRun.latest.success).to eq false
    end

    it 'does nothing for an unknown subject' do
      expect(CloudModel::BackupRun).not_to receive(:start!)

      subject.perform 'replication_set', BSON::ObjectId.new.to_s
    end
  end

  describe '.resolve_subject' do
    it 'finds replica sets' do
      expect(described_class.resolve_subject('replication_set', set.id.to_s)).to eq set
    end

    it 'returns nil for unknown types and missing documents' do
      expect(described_class.resolve_subject('nonsense', set.id.to_s)).to be_nil
      expect(described_class.resolve_subject('replication_set', BSON::ObjectId.new.to_s)).to be_nil
    end
  end
end
