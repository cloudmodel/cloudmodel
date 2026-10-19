require 'spec_helper'

describe CloudModel::ContainerCleanup do
  let(:host) { double CloudModel::Host, name: 'host-a' }
  let(:current) { double 'current', name: 'g-3', created_at: Time.new(2026, 10, 19), running?: true, host: host, root_dataset: 'guests/containers/g-3' }
  let(:previous) { double 'previous', name: 'g-2', created_at: Time.new(2026, 9, 1), running?: false, host: host, root_dataset: 'guests/containers/g-2' }
  let(:older) { double 'older', name: 'g-1', created_at: Time.new(2025, 1, 1), running?: false, host: host, root_dataset: 'guests/containers/g-1' }
  let(:oldest) { double 'oldest', name: 'g-0', created_at: Time.new(2024, 1, 1), running?: false, host: host, root_dataset: 'guests/containers/g-0' }
  let(:containers) { double 'containers', to_a: [older, current, oldest, previous], count: 4 }
  let(:guest) { double CloudModel::Guest, name: 'g', host: host, lxd_containers: containers, current_lxd_container: current }

  subject { described_class.new keep: 2 }

  before do
    allow(host).to receive(:exec).with(/zfs list .* guests\/containers\/g-1/).and_return [true, "#{40 * 1024**3}\n"]
    allow(host).to receive(:exec).with(/zfs list .* guests\/containers\/g-0/).and_return [true, "#{2 * 1024**3}\n"]
  end

  it 'keeps the newest `keep` containers and marks the older stopped ones removable' do
    expect(subject.removable([guest])).to eq [[guest, [older, oldest]]]
  end

  it 'never marks the running container removable, whatever its age' do
    old_running = double 'running but old', name: 'g-r', created_at: Time.new(2020, 1, 1), running?: true, host: host, root_dataset: 'guests/containers/g-r'
    allow(containers).to receive(:to_a).and_return [older, current, oldest, previous, old_running]
    allow(guest).to receive(:current_lxd_container).and_return old_running
    expect(subject.removable([guest]).first.last).not_to include old_running
  end

  it 'reports only in a dry run, with the space it would free' do
    out = StringIO.new
    expect(older).not_to receive(:destroy)
    result = subject.cleanup! [guest], dry_run: true, output: out
    expect(out.string).to include 'would remove g-1 (40.0G)'
    expect(out.string).to include 'would remove g-0 (2.0G)'
    expect(out.string).to include 'would free about 42.0G'
    expect(result).to eq(removed: 0, failed: 0, bytes: 42 * 1024**3)
  end

  it 'destroys the stale containers (lxc delete through the model) and carries on after a failure' do
    out = StringIO.new
    expect(older).to receive(:destroy).and_return true
    expect(oldest).to receive(:destroy).and_raise('lxc delete failed')
    allow(CloudModel).to receive(:log_exception)
    result = subject.cleanup! [guest], dry_run: false, output: out
    expect(out.string).to include 'removed g-1'
    expect(out.string).to include 'FAILED  g-0: lxc delete failed'
    expect(result[:removed]).to eq 1
    expect(result[:failed]).to eq 1
  end

  it 'skips a stale container that turns out to be running' do
    allow(older).to receive(:running?).and_return true
    out = StringIO.new
    expect(older).not_to receive(:destroy)
    allow(oldest).to receive(:destroy).and_return true
    subject.cleanup! [guest], dry_run: false, output: out
    expect(out.string).to include 'keep    g-1 — running'
  end
end
