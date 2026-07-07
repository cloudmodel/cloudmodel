# encoding: UTF-8

require 'spec_helper'

describe CloudModel::BackupRun do
  it { expect(subject).to have_field(:started_at).of_type(Time) }
  it { expect(subject).to have_field(:finished_at).of_type(Time) }
  it { expect(subject).to have_field(:log).of_type(String) }
  it { expect(subject).to have_field(:total_subjects).of_type(Integer) }
  it { expect(subject).to have_field(:finished_subjects).of_type(Integer) }

  describe '.start!' do
    it 'creates a running run and fails stale unfinished ones' do
      stale = CloudModel::BackupRun.create! started_at: 1.hour.ago

      run = CloudModel::BackupRun.start! total_subjects: 5

      expect(run.active?).to eq true
      expect(run.total_subjects).to eq 5
      expect(stale.reload.active?).to eq false
      expect(stale.success).to eq false
      expect(stale.log).to match(/superseded/)
    end
  end

  describe 'append_log / flush_log' do
    it 'buffers appends and persists them on flush' do
      run = CloudModel::BackupRun.create! started_at: Time.now
      run.append_log "line 1\n" # first append flushes immediately
      run.append_log "line 2\n" # buffered (within FLUSH_INTERVAL)
      run.flush_log

      expect(run.reload.log).to eq "line 1\nline 2\n"
    end

    it 'keeps a rolling tail beyond the limit' do
      run = CloudModel::BackupRun.create! started_at: Time.now
      stub_const 'CloudModel::BackupRun::LOG_LIMIT', 10
      run.append_log 'abcdefghij'
      run.append_log 'KLMNO'
      run.flush_log

      expect(run.reload.log).to start_with "… (truncated)\n"
      expect(run.log).to end_with 'KLMNO'
    end
  end

  describe 'progress' do
    it 'tracks finished subjects as percent' do
      run = CloudModel::BackupRun.create! started_at: Time.now, total_subjects: 4
      2.times { run.subject_finished! }

      expect(run.reload.finished_subjects).to eq 2
      expect(run.progress_percent).to eq 50
    end

    it 'is 0 without subjects and capped at 100' do
      expect(CloudModel::BackupRun.new.progress_percent).to eq 0
      run = CloudModel::BackupRun.new total_subjects: 2, finished_subjects: 5
      expect(run.progress_percent).to eq 100
    end
  end

  describe 'finish!' do
    it 'flushes the log and closes the run' do
      run = CloudModel::BackupRun.create! started_at: Time.now
      run.append_log "done\n"
      run.finish! success: true

      expect(run.reload.active?).to eq false
      expect(run.success).to eq true
      expect(run.log).to eq "done\n"
    end
  end
end
