require 'spec_helper'

describe CloudModel::RubyPatch do
  let(:host) { double CloudModel::Host, name: 'host-a', arch: 'amd64' }
  let(:container) { double 'container', name: 'g-3' }
  let(:guest) { double CloudModel::Guest, name: 'web', host: host, os_version: 'debian-12', current_lxd_container: container }
  let(:out) { StringIO.new }
  let(:dataset) { 'guests/build/ruby/3.4.13/debian-12-amd64' }
  let(:mountpoint) { '/cloud/build/ruby/3.4.13/debian-12-amd64' }

  subject { described_class.new version: '3.4.13', output: out }

  before { allow(CloudModel.config).to receive(:build_dataset).and_return 'guests/build' }

  # the script a `bash -c <script>` command carries
  def script_of command
    Shellwords.split(command).last
  end

  let(:old_inventory) do
    <<~OUT
      default=3.4.8
      installed=ruby-3.4.8
      app=/var/www/rails/current|2.5.4|ruby-3.4.8
      running=3.4.8
      units=delayed_jobs@default.service rake-index.service
      os=debian-12
      arch=amd64
    OUT
  end

  let(:new_inventory) do
    old_inventory.sub('default=3.4.8', 'default=3.4.13').sub('|ruby-3.4.8', '|ruby-3.4.13').sub('running=3.4.8', 'running=3.4.13').sub('installed=ruby-3.4.8', 'installed=ruby-3.4.8 ruby-3.4.13')
  end

  it 'refuses anything but a full version' do
    expect { described_class.new version: '3.4' }.to raise_error ArgumentError
  end

  describe '.guests_with_ruby' do
    it 'keeps guests whose nginx runs Passenger or Capistrano apps' do
      passenger = double 'nginx', passenger_supported: true, capistrano_supported: false
      proxy = double 'nginx', passenger_supported: false, capistrano_supported: false
      allow(passenger).to receive(:is_a?).with(CloudModel::Services::Nginx).and_return true
      allow(proxy).to receive(:is_a?).with(CloudModel::Services::Nginx).and_return true
      with = double 'guest', services: [passenger]
      without = double 'guest', services: [proxy]
      expect(described_class.guests_with_ruby([with, without])).to eq [with]
    end
  end

  describe '#inventory' do
    it 'parses the guest report' do
      expect(guest).to receive(:exec).with(/readlink/).and_return [true, old_inventory]
      inv = subject.inventory guest
      expect(inv[:default]).to eq '3.4.8'
      expect(inv[:installed]).to eq ['ruby-3.4.8']
      expect(inv[:apps]).to eq [{ dir: '/var/www/rails/current', bundled_with: '2.5.4', ruby_version: '3.4.8' }]
      expect(inv[:running]).to eq ['3.4.8']
      expect(inv[:units]).to eq ['delayed_jobs@default.service', 'rake-index.service']
      expect(inv[:arch]).to eq 'amd64'
      expect(subject.up_to_date?(inv)).to be false
      expect(subject.same_line?(inv)).to be true
    end

    it 'is current only when default, every .ruby-version and every running interpreter are the release' do
      expect(guest).to receive(:exec).and_return [true, new_inventory], [true, new_inventory.sub('|ruby-3.4.13', '|3.4.11')], [true, new_inventory.sub('running=3.4.13', 'running=3.4.11 3.4.13')], [true, new_inventory.sub("running=3.4.13\n", "running=\n")]
      expect(subject.up_to_date?(subject.inventory(guest))).to be true
      expect(subject.up_to_date?(subject.inventory(guest))).to be false
      expect(subject.up_to_date?(subject.inventory(guest))).to be false
      expect(subject.up_to_date?(subject.inventory(guest))).to be true
    end

    it 'knows a guest on another minor line' do
      expect(guest).to receive(:exec).and_return [true, old_inventory.sub('default=3.4.8', 'default=2.5.9')]
      expect(subject.same_line?(subject.inventory(guest))).to be false
    end
  end

  describe '#volume_on' do
    it 'names the ruby volume per release and os/arch' do
      vol = subject.volume_on host, 'debian-12', 'amd64'
      expect(vol.dataset_name).to eq dataset
      expect(vol.mountpoint).to eq mountpoint
    end
  end

  describe '#patch!' do
    it 'counts a guest already on the version as current and leaves it alone' do
      expect(guest).to receive(:exec).once.and_return [true, new_inventory]
      counts = subject.patch! [guest], dry_run: false
      expect(counts).to eq(patched: 0, current: 1, skipped: 0, failed: 0)
      expect(out.string).to include 'on 3.4.13'
    end

    it 'skips a guest on another minor line and never touches it' do
      expect(guest).to receive(:exec).once.and_return [true, old_inventory.sub('default=3.4.8', 'default=2.5.9')]
      expect(guest).not_to receive(:exec!)
      counts = subject.patch! [guest], dry_run: false
      expect(counts).to eq(patched: 0, current: 0, skipped: 1, failed: 0)
      expect(out.string).to include 'skipped'
      expect(out.string).to include '2.5.9 is not on the 3.4 line'
    end

    it 'leaves out a guest whose architecture does not match its host' do
      expect(guest).to receive(:exec).once.and_return [true, old_inventory.sub('arch=amd64', 'arch=arm64')]
      counts = subject.patch! [guest], dry_run: true
      expect(counts[:failed]).to eq 1
      expect(out.string).to include 'guest reports arch arm64'
    end

    it 'reports a missing build host in the dry run' do
      allow(CloudModel::Host).to receive(:build_host).with('amd64').and_return nil
      allow(CloudModel::GuestTemplate).to receive(:where).and_return double('templates', order: double('ordered', to_a: []))
      expect(guest).to receive(:exec).once.and_return [true, old_inventory]
      counts = subject.patch! [guest], dry_run: true
      expect(out.string).to include 'no build host for debian-12 amd64'
      expect(counts).to eq(patched: 0, current: 0, skipped: 0, failed: 0)
    end

    context 'with a build host and a finished template of the os/arch' do
      let(:build_host) { double CloudModel::Host, name: 'build-host', arch: 'amd64' }
      let(:template_type) { double 'type', components: ['nginx', 'ruby@3.4'] }
      let(:template) { double CloudModel::GuestTemplate, id: 'tpl1', template_type: template_type }
      let(:worker) { double CloudModel::Workers::RubyBuildWorker }
      let(:build_volume) { double 'volume on build host', dataset_name: dataset, mountpoint: mountpoint }
      let(:host_volume) { double 'volume on host-a', dataset_name: dataset, mountpoint: mountpoint }

      before do
        allow(CloudModel::Host).to receive(:build_host).with('amd64').and_return build_host
        templates = double 'templates'
        allow(CloudModel::GuestTemplate).to receive(:where).with(os_version: 'debian-12', arch: 'amd64', build_state_id: 0xf0).and_return templates
        allow(templates).to receive(:order).with(created_at: :desc).and_return double('ordered', to_a: [template])
        allow(CloudModel::BuildZfsVolume).to receive(:new).with(build_host, dataset, mountpoint: mountpoint).and_return build_volume
        allow(CloudModel::BuildZfsVolume).to receive(:new).with(host, dataset, mountpoint: mountpoint).and_return host_volume
      end

      it 'names the build host, template and sync targets in the dry run, and changes nothing' do
        allow(build_volume).to receive(:ready?).and_return false
        expect(guest).to receive(:exec).once.and_return [true, old_inventory]
        expect(guest).not_to receive(:exec!)
        counts = subject.patch! [guest], dry_run: true
        expect(out.string).to include '3.4.8 → 3.4.13'
        expect(out.string).to include 'would compile ruby-3.4.13 on build-host in a clone of template tpl1 (nginx,ruby@3.4), sync it to host-a, then patch 1 guest(s)'
        expect(counts).to eq(patched: 0, current: 0, skipped: 0, failed: 0)
      end

      it 'says so in the dry run when the volume is already built' do
        allow(build_volume).to receive(:ready?).and_return true
        expect(guest).to receive(:exec).once.and_return [true, old_inventory]
        subject.patch! [guest], dry_run: true
        expect(out.string).to include 'would reuse the ruby-3.4.13 volume on build-host, sync it to host-a'
      end

      before { allow(subject).to receive(:sleep) }

      it 'compiles on the build host, syncs the volume to the guests\' host, unpacks and switches every guest, and verifies' do
        other_container = double 'container', name: 'api-1'
        other = double CloudModel::Guest, name: 'api', host: host, os_version: 'debian-12', current_lxd_container: other_container
        # inventory before, then after the switch — for both guests
        expect(guest).to receive(:exec).with(/readlink/).and_return [true, old_inventory], [true, new_inventory]
        expect(other).to receive(:exec).with(/readlink/).and_return [true, old_inventory], [true, new_inventory]

        expect(build_volume).to receive(:ready?).and_return false
        expect(CloudModel::Workers::RubyBuildWorker).to receive(:new).with(build_host, template: template, version: '3.4.13', volume: build_volume, rvm_update: false).and_return worker
        expect(worker).to receive(:build!).ordered
        expect(host_volume).to receive(:ready?).and_return false
        expect(subject).to receive(:sync_zfs_dataset!).with(build_host, host, dataset).ordered
        expect(host_volume).to receive(:mount!).ordered

        # unpack from the mounted volume into both guests, switch
        expect(host).to receive(:exec!).with("tar -C #{mountpoint} -cf - rubies gems environments wrappers | /usr/bin/lxc exec api-1 -- tar -C /usr/local/rvm -xf -", /unpacking/)
        expect(host).to receive(:exec!).with("tar -C #{mountpoint} -cf - rubies gems environments wrappers | /usr/bin/lxc exec g-3 -- tar -C /usr/local/rvm -xf -", /unpacking/)
        [other, guest].each do |g|
          expect(g).to receive(:exec!).with(/\Abash -c /, /switching/) do |command, _msg|
            script = script_of command
            expect(script).to include 'rvm ruby-3.4.13 do gem install bundler -v 2.5.4'
            expect(script).to include 'cd /var/www/rails/current && /usr/local/rvm/bin/rvm ruby-3.4.13 do bundle check'
            expect(script).to include 'rvm alias create default ruby-3.4.13'
            expect(script).to include 'echo ruby-3.4.13 > /var/www/rails/current/.ruby-version'
            expect(script).to include 'passenger-config restart-app /var/www/rails/current --ignore-app-not-running'
            expect(script).to include 'systemctl try-restart delayed_jobs@default.service'
            expect(script).to include 'systemctl try-restart rake-index.service'
            expect(script).not_to include 'nginx'
            expect(script.index('bundle check')).to be < script.index('alias create default')
            expect(script.index('alias create default')).to be < script.index('.ruby-version')
            expect(script.index('.ruby-version')).to be < script.index('restart-app')
            'ok'
          end
        end

        counts = subject.patch! [guest, other], dry_run: false
        expect(counts).to eq(patched: 2, current: 0, skipped: 0, failed: 0)
        expect(out.string).to include 'compiling ruby-3.4.13 on build-host in a clone of template tpl1'
        expect(out.string).to include 'syncing ruby-3.4.13 volume build-host → host-a'
      end

      it 'reuses a built volume, skips the sync where the volume is present, and reports a failed switch with the rollback' do
        expect(guest).to receive(:exec).with(/readlink/).and_return [true, old_inventory]
        expect(build_volume).to receive(:ready?).and_return true
        expect(CloudModel::Workers::RubyBuildWorker).not_to receive(:new)
        expect(host_volume).to receive(:ready?).and_return true
        expect(subject).not_to receive(:sync_zfs_dataset!)
        expect(host_volume).to receive(:mount!)
        expect(host).to receive(:exec!).with(/tar -C #{mountpoint} -cf -/, /unpacking/)
        expect(guest).to receive(:exec!).with(/\Abash -c /, /switching/).and_raise "switching web to ruby-3.4.13 failed:\n\nbundle check failed in /var/www/rails/current"

        counts = subject.patch! [guest], dry_run: false
        expect(counts).to eq(patched: 0, current: 0, skipped: 0, failed: 1)
        expect(out.string).to include 'ruby-3.4.13 volume ready on build-host'
        expect(out.string).to match %r{FAILED\e\[39m \(bundle check failed in /var/www/rails/current\)}
        expect(out.string).to include 'rvm alias create default ruby-3.4.8; echo 3.4.8 > /var/www/rails/current/.ruby-version'
      end

      it 'fails a guest whose processes still run the old interpreter after the switch' do
        expect(guest).to receive(:exec).with(/readlink/).and_return [true, old_inventory], *([[true, new_inventory.sub('running=3.4.13', 'running=3.4.8 3.4.13')]] * 6)
        allow(build_volume).to receive(:ready?).and_return true
        allow(host_volume).to receive(:ready?).and_return true
        allow(host_volume).to receive(:mount!)
        allow(host).to receive(:exec!)
        expect(guest).to receive(:exec!).with(/\Abash -c /, /switching/)
        counts = subject.patch! [guest], dry_run: false
        expect(counts[:failed]).to eq 1
        expect(out.string).to include 'guest still runs 3.4.8 after the switch'
      end

      it 'reports a guest without a ruby process yet as patched with a note' do
        expect(guest).to receive(:exec).with(/readlink/).and_return [true, old_inventory], [true, new_inventory.sub("running=3.4.13\n", "running=\n")]
        allow(build_volume).to receive(:ready?).and_return true
        allow(host_volume).to receive(:ready?).and_return true
        allow(host_volume).to receive(:mount!)
        allow(host).to receive(:exec!)
        expect(guest).to receive(:exec!).with(/\Abash -c /, /switching/)
        counts = subject.patch! [guest], dry_run: false
        expect(counts[:patched]).to eq 1
        expect(out.string).to include 'no ruby process running yet'
      end

      it 'does not unpack from the build host itself through a sync' do
        local_guest = double CloudModel::Guest, name: 'on-build', host: build_host, os_version: 'debian-12', current_lxd_container: double('c', name: 'b-1')
        expect(local_guest).to receive(:exec).with(/readlink/).and_return [true, old_inventory], [true, new_inventory]
        expect(build_volume).to receive(:ready?).and_return true, true
        expect(subject).not_to receive(:sync_zfs_dataset!)
        expect(build_volume).to receive(:mount!)
        expect(build_host).to receive(:exec!).with(/tar -C #{mountpoint} -cf -.*lxc exec b-1/, /unpacking/)
        expect(local_guest).to receive(:exec!).with(/\Abash -c /, /switching/)
        expect(subject.patch!([local_guest], dry_run: false)).to eq(patched: 1, current: 0, skipped: 0, failed: 0)
      end

      it 'fails the whole group when the build fails, without touching a guest' do
        expect(guest).to receive(:exec).with(/readlink/).and_return [true, old_inventory]
        expect(build_volume).to receive(:ready?).and_return false
        expect(CloudModel::Workers::RubyBuildWorker).to receive(:new).and_return worker
        expect(worker).to receive(:build!).and_raise "rvm install ruby-3.4.13 failed on build-host:\n\nUnknown ruby"
        expect(guest).not_to receive(:exec!)
        counts = subject.patch! [guest], dry_run: false
        expect(counts).to eq(patched: 0, current: 0, skipped: 0, failed: 1)
        expect(out.string).to include 'build FAILED'
      end

      it 'fails the guests of a host whose sync fails and patches the others' do
        other_host = double CloudModel::Host, name: 'host-b', arch: 'amd64'
        other_volume = double 'volume on host-b', dataset_name: dataset, mountpoint: mountpoint
        allow(CloudModel::BuildZfsVolume).to receive(:new).with(other_host, dataset, mountpoint: mountpoint).and_return other_volume
        other = double CloudModel::Guest, name: 'api', host: other_host, os_version: 'debian-12', current_lxd_container: double('c', name: 'api-1')
        expect(guest).to receive(:exec).with(/readlink/).and_return [true, old_inventory], [true, new_inventory]
        expect(other).to receive(:exec).with(/readlink/).and_return [true, old_inventory]
        allow(build_volume).to receive(:ready?).and_return true
        allow(host_volume).to receive(:ready?).and_return true
        allow(host_volume).to receive(:mount!)
        allow(other_volume).to receive(:ready?).and_return false
        expect(subject).to receive(:sync_zfs_dataset!).with(build_host, other_host, dataset).and_raise 'Failed to sync build volume (direct)'
        expect(host).to receive(:exec!).with(/unpacking|tar/, anything)
        expect(guest).to receive(:exec!).with(/\Abash -c /, /switching/)
        expect(other).not_to receive(:exec!)

        counts = subject.patch! [guest, other], dry_run: false
        expect(counts).to eq(patched: 1, current: 0, skipped: 0, failed: 1)
        expect(out.string).to include 'sync to host-b FAILED'
      end
    end
  end
end
