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

  it 'captures stdout into the log and keeps the console quiet by default' do
    expect {
      subject.with_live_log { puts 'working...' }
    }.not_to output.to_stdout

    expect(subject.reload.live_log).to eq "working...\n"
  end

  it 'passes stdout through with verbose: true' do
    expect {
      subject.with_live_log(verbose: true) { puts 'working...' }
    }.to output("working...\n").to_stdout

    expect(subject.reload.live_log).to eq "working...\n"
  end

  it 'tracks the current step and resets it on the next run' do
    subject.with_live_log do
      subject.set_live_log_step 'Install basic utils', counter: '3', total: 12
    end
    expect(subject.reload.live_log_step).to eq 'Install basic utils'

    subject.restart_live_log
    expect(subject.reload.live_log_step).to be_nil
  end

  it 'keeps the last step and appends the error when the flow raises' do
    expect {
      subject.with_live_log do
        subject.set_live_log_step 'Install basic utils', counter: '3', total: 12
        raise 'boom'
      end
    }.to raise_error 'boom'

    expect(subject.reload.live_log_step).to eq 'Install basic utils'
    expect(subject.live_log).to include 'RuntimeError: boom'
  end

  it 'registers itself as the current live log subject while running' do
    seen = nil
    subject.with_live_log { seen = CloudModel.current_live_log_subject }

    expect(seen).to eq subject
    expect(CloudModel.current_live_log_subject).to be_nil
  end

  it 'never raises on bookkeeping errors' do
    subject.restart_live_log
    allow(subject).to receive(:set).and_raise('db gone')

    expect { subject.append_live_log 'x' }.not_to raise_error
  end
end
