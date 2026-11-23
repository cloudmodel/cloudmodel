require 'spec_helper'

describe CloudModel::RubyReleasePatch do
  let(:out) { StringIO.new }
  let(:host) { double CloudModel::Host, name: 'core-a', arch: 'amd64' }
  let(:build_host) { double CloudModel::Host, name: 'build-host', arch: 'amd64' }
  let(:issues) { double 'issues', find_or_initialize_by: double('issue', :severity= => nil, :message= => nil, save: true), where: double('scope', update_all: 1) }
  let(:index) { { '3.4.13' => { url: 'u', sha256: 'a' * 64 }, '3.4.14' => { url: 'u', sha256: 'b' * 64 }, '4.0.1' => { url: 'u', sha256: 'c' * 64 } } }
  subject { described_class.new output: out, index: index }

  def guest_double name, lines: ['3.4'], explicit: [], os: 'debian-12'
    double CloudModel::Guest, name: name, host: host, os_version: os, deploy_state: :finished,
      ruby_lines_needed: lines, ruby_default_line: lines.first, ruby_lines: explicit, item_issues: issues
  end

  def inventory_output layout: 'mount', default: '3.4', current: '3.4.13', installed: %w(3.4.13), passenger: %w(3.4.13), other: %w(3.4.13)
    return "layout=rvm\n" if layout == 'rvm'
    <<~OUT
      layout=mount
      default=#{default}
      current=#{current}
      installed=#{installed.join(' ')}
      passenger_running=#{passenger.join(' ')}
      other_running=#{other.join(' ')}
      apps=/var/www/rails/current
      units=delayed_jobs@default.service rake-index.service
    OUT
  end

  before do
    allow(subject).to receive(:sleep)
    allow(CloudModel::Host).to receive(:build_host).with('amd64').and_return build_host
  end

  describe '.guests_with_ruby' do
    it 'takes running guests with a Ruby line' do
      a = double 'a', deploy_state: :finished, ruby_lines_needed: ['3.4']
      b = double 'b', deploy_state: :finished, ruby_lines_needed: []
      c = double 'c', deploy_state: :pending, ruby_lines_needed: ['3.4']
      d = double 'd', deploy_state: :failed, ruby_lines_needed: ['4.0']
      expect(described_class.guests_with_ruby([a, b, c, d])).to eq [a, d]
    end
  end

  describe '#release_targets' do
    it 'names the newest release in the index for every os/arch/line in use' do
      guests = [guest_double('web', lines: %w(3.4)), guest_double('ci', lines: %w(3.4 4.0)), guest_double('old', lines: %w(3.3))]
      expect(subject.release_targets(guests)).to eq(
        ['debian-12', 'amd64', '3.4'] => '3.4.14',
        ['debian-12', 'amd64', '4.0'] => '4.0.1',
        ['debian-12', 'amd64', '3.3'] => nil
      )
    end
  end

  describe '#patch!' do
    let(:guest) { guest_double 'web' }
    let(:release) { double 'release', name: 'ruby-3.4.14', build_host: build_host }

    before do
      allow(CloudModel::RubyRelease).to receive(:new).with(version: '3.4.14', os_version: 'debian-12', arch: 'amd64').and_return release
    end

    it 'plans the build and sync in the dry run and touches nothing' do
      allow(release).to receive(:present_on?).and_return false
      allow(guest).to receive(:exec).and_return [true, inventory_output]
      expect(release).not_to receive(:ensure_built!)
      expect(guest).not_to receive(:exec!)
      counts = subject.patch! [guest], dry_run: true
      expect(out.string).to include 'would build ruby-3.4.14 for debian-12 amd64 on build-host and sync it to core-a'
      expect(out.string).to include 'web@core-a: on 3.4.13'
      expect(counts[:built]).to eq 0
    end

    it 'builds on the build host, syncs to the guests\' hosts, points current at the new release, restarts and verifies' do
      allow(release).to receive(:present_on?).with(build_host).and_return false, true
      allow(release).to receive(:present_on?).with(host).and_return false
      expect(release).to receive(:ensure_built!).with(output: out).ordered
      expect(release).to receive(:ensure_on!).with(host, output: out).ordered
      running = %w(3.4.13)
      allow(guest).to receive(:exec).with(/readlink/) { [true, inventory_output(installed: %w(3.4.13 3.4.14), passenger: running, other: running)] }
      expect(guest).to receive(:exec!).with(/ruby-3\.4\.14/, anything) do |cmd, _msg|
        script = Shellwords.split(cmd).last
        expect(script).to include "ln -sfn /opt/ruby/ruby-3.4.14 /usr/local/ruby/current"
        expect(script).to include "passenger-config restart-app /var/www/rails --ignore-app-not-running"
        expect(script).to include "systemctl --no-block try-restart delayed_jobs@default.service"
        running.replace %w(3.4.14)
        ''
      end
      counts = subject.patch! [guest], dry_run: false
      expect(counts).to include built: 1, synced: 1, patched: 1, failed: 0
      expect(out.string).to match(/web@core-a: .*patched.* to 3\.4\.14/)
    end

    it 'leaves a guest on the newest release alone and skips the RVM layout' do
      allow(release).to receive(:present_on?).and_return true
      allow(guest).to receive(:exec).and_return [true, inventory_output(current: '3.4.14', installed: %w(3.4.13 3.4.14), passenger: %w(3.4.14), other: %w(3.4.14))]
      rvm = guest_double 'legacy'
      allow(rvm).to receive(:exec).and_return [true, inventory_output(layout: 'rvm')]
      counts = subject.patch! [guest, rvm], dry_run: false
      expect(counts).to include current: 1, skipped: 1, patched: 0
      expect(out.string).to include 'legacy@core-a'
      expect(out.string).to include 'RVM layout'
    end

    it 'leaves a pinned guest on its pin and notes the newer release as an issue' do
      pinned = guest_double 'pinned', lines: %w(3.4), explicit: %w(3.4.13)
      allow(release).to receive(:present_on?).and_return true
      allow(pinned).to receive(:exec).and_return [true, inventory_output(current: '3.4.13', installed: %w(3.4.13 3.4.14))]
      expect(issues).to receive(:find_or_initialize_by).with(key: :ruby_pinned_behind, resolved_at: nil).and_return double('issue', :severity= => nil, :message= => nil, save: true)
      expect(pinned).not_to receive(:exec!)
      counts = subject.patch! [pinned], dry_run: false
      expect(counts[:current]).to eq 1
      expect(out.string).to include 'on 3.4.13 (pinned)'
    end

    it 'fails a guest whose processes still run the old release after the switch, with an issue' do
      allow(release).to receive(:present_on?).and_return true
      allow(guest).to receive(:exec).and_return [true, inventory_output(installed: %w(3.4.13 3.4.14))]
      allow(guest).to receive(:exec!).and_return ''
      expect(issues).to receive(:find_or_initialize_by).with(key: :ruby_patch, resolved_at: nil)
      counts = subject.patch! [guest], dry_run: false
      expect(counts[:failed]).to eq 1
      expect(out.string).to include 'still running 3.4.13 after the switch'
    end

    it 'defers guests past the deadline' do
      patch = described_class.new output: out, index: index, deadline: Time.now - 60
      allow(release).to receive(:present_on?).and_return true
      expect(guest).not_to receive(:exec)
      counts = patch.patch! [guest], dry_run: false
      expect(counts[:deferred]).to eq 1
    end
  end

  describe '.nightly!' do
    it 'does nothing when switched off or outside the window' do
      allow(CloudModel.config).to receive(:ruby_unattended).and_return false
      expect(described_class.nightly!(output: out)).to be_nil
      allow(CloudModel.config).to receive(:ruby_unattended).and_return true
      expect(described_class.nightly!(output: out, now: Time.utc(2026, 11, 24, 10, 0))).to be_nil
      expect(out.string).to include 'switched off'
      expect(out.string).to include 'starts between 23:00 and 02:00 UTC only'
    end
  end
end
