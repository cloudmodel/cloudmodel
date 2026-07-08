require 'spec_helper'

describe CloudModel::Mixins::LiveLog do
  subject { CloudModel::SolrImage.create! name: "live-log-#{SecureRandom.hex 4}", git_server: 'git', git_repo: 'repo', git_branch: 'master' }

  after { subject.delete }

  it 'starts fresh and stamps the start time' do
    subject.set live_log: 'old run'
    subject.restart_live_log

    subject.reload
    expect(subject.live_log).to eq ''
    expect(subject.live_log_started_at).to be_within(5.seconds).of Time.now
  end

  it 'buffers appends and flushes them combined' do
    subject.restart_live_log
    subject.append_live_log "line 1\n"   # first append flushes immediately
    subject.append_live_log "line 2\n"   # buffered (within FLUSH_INTERVAL)
    subject.flush_live_log

    expect(subject.reload.live_log).to eq "line 1\nline 2\n"
  end

  it 'keeps a rolling tail above LOG_LIMIT' do
    subject.restart_live_log
    subject.append_live_log 'x' * (described_class::LOG_LIMIT + 100)
    subject.flush_live_log

    log = subject.reload.live_log
    expect(log).to start_with '… (truncated)'
    expect(log.length).to be <= described_class::LOG_LIMIT + 20
  end

  it 'never raises on bookkeeping errors' do
    subject.restart_live_log
    allow(subject).to receive(:set).and_raise('db gone')

    expect { subject.append_live_log 'x' }.not_to raise_error
  end
end
