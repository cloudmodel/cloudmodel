require 'spec_helper'
require 'tmpdir'

describe CloudModel::RubyPatch do
  let(:sftp) { double 'sftp' }
  let(:host) { double CloudModel::Host, name: 'host-a', arch: 'amd64', sftp: sftp }
  let(:container) { double 'container', name: 'g-3' }
  let(:guest) { double CloudModel::Guest, name: 'web', host: host, os_version: 'debian-12', current_lxd_container: container }
  let(:local_dir) { Dir.mktmpdir }
  let(:out) { StringIO.new }
  let(:archive) { 'cloudmodel-ruby-3.4.13-debian-12-amd64.tar.gz' }

  subject { described_class.new version: '3.4.13', local_dir: local_dir, output: out }

  after { FileUtils.rm_rf local_dir }

  # the script a `bash -c <script>` command carries
  def script_of command
    Shellwords.split(command).last
  end

  let(:old_inventory) do
    <<~OUT
      default=3.4.8
      installed=ruby-3.4.8
      passenger_ruby=/usr/local/rvm/rubies/ruby-3.4.8/bin/ruby
      passenger_version=6.0.23
      app=/var/www/rails/current|2.5.4
      units=delayed_jobs@default.service rake-index.service
      os=debian-12
      arch=amd64
    OUT
  end

  let(:new_inventory) do
    old_inventory.sub('default=3.4.8', 'default=3.4.13').sub('ruby-3.4.8/bin', 'ruby-3.4.13/bin').sub('installed=ruby-3.4.8', 'installed=ruby-3.4.8 ruby-3.4.13')
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
      expect(guest).to receive(:exec).with(/passenger_ruby/).and_return [true, old_inventory]
      inv = subject.inventory guest
      expect(inv[:default]).to eq '3.4.8'
      expect(inv[:installed]).to eq ['ruby-3.4.8']
      expect(inv[:passenger_ruby]).to eq '/usr/local/rvm/rubies/ruby-3.4.8/bin/ruby'
      expect(inv[:apps]).to eq [{ dir: '/var/www/rails/current', bundled_with: '2.5.4' }]
      expect(inv[:units]).to eq ['delayed_jobs@default.service', 'rake-index.service']
      expect(inv[:arch]).to eq 'amd64'
      expect(subject.up_to_date?(inv)).to be false
    end

    it 'treats a guest without passenger.conf as current once the default ruby matches' do
      expect(guest).to receive(:exec).and_return [true, new_inventory.sub(/passenger_ruby=.*\n/, "passenger_ruby=\n")]
      expect(subject.up_to_date?(subject.inventory(guest))).to be true
    end
  end

  describe '#patch!' do
    it 'only reports in a dry run' do
      expect(guest).to receive(:exec).once.and_return [true, old_inventory]
      expect(guest).not_to receive(:exec!)
      counts = subject.patch! [guest], dry_run: true
      expect(out.string).to include '3.4.8 → 3.4.13'
      expect(out.string).to include 'would compile ruby-3.4.13 in web @ host-a'
      expect(counts).to eq(patched: 0, current: 0, failed: 0)
    end

    it 'counts a guest already on the version as current and leaves it alone' do
      expect(guest).to receive(:exec).once.and_return [true, new_inventory]
      counts = subject.patch! [guest], dry_run: false
      expect(counts).to eq(patched: 0, current: 1, failed: 0)
      expect(out.string).to include 'on 3.4.13'
    end

    it 'leaves out a guest whose architecture does not match its host' do
      expect(guest).to receive(:exec).once.and_return [true, old_inventory.sub('arch=amd64', 'arch=arm64')]
      counts = subject.patch! [guest], dry_run: true
      expect(counts[:failed]).to eq 1
      expect(out.string).to include 'guest reports arch arm64'
    end

    it 'compiles in the build guest, pulls the archive, unpacks and switches every guest, and verifies' do
      other_container = double 'container', name: 'api-1'
      other = double CloudModel::Guest, name: 'api', host: host, os_version: 'debian-12', current_lxd_container: other_container
      # inventory before, then after the switch — for both guests
      expect(guest).to receive(:exec).with(/passenger_ruby/).and_return [true, old_inventory], [true, new_inventory]
      expect(other).to receive(:exec).with(/passenger_ruby/).and_return [true, old_inventory], [true, new_inventory]

      # build in the first guest (api sorts before web), pack on the host, download
      expect(other).to receive(:exec!).with(/\Abash -c /, /rvm install/) do |command, _msg|
        expect(script_of(command)).to include "/usr/local/rvm/bin/rvm install ruby-3.4.13 --disable-binary --autolibs=read-fail"
        'ok'
      end.ordered
      expect(host).to receive(:exec!).with(%r{\A/usr/bin/lxc exec api-1 -- bash -c .* \| gzip -1 > /tmp/#{archive}\z}, /packing/) do |command, _msg|
        pack = script_of command.split(' | ').first
        expect(pack).to eq 'cd /usr/local/rvm && tar -cf - rubies/ruby-3.4.13 gems/ruby-3.4.13* environments/ruby-3.4.13* wrappers/ruby-3.4.13*'
        'ok'
      end.ordered
      expect(sftp).to receive(:download!).with("/tmp/#{archive}", "#{local_dir}/#{archive}") do |_remote, local|
        File.write local, 'tgz'
      end.ordered

      # the archive is on this host already: unpack into both guests, switch
      allow(host).to receive(:exec).with("test -f /tmp/#{archive}").and_return [true, '']
      expect(sftp).not_to receive(:upload!)
      expect(host).to receive(:exec!).with("/usr/bin/lxc exec api-1 -- tar -C /usr/local/rvm -xzf - < /tmp/#{archive}", /unpacking/)
      expect(host).to receive(:exec!).with("/usr/bin/lxc exec g-3 -- tar -C /usr/local/rvm -xzf - < /tmp/#{archive}", /unpacking/)
      [other, guest].each do |g|
        expect(g).to receive(:exec!).with(/\Abash -c /, /switching/) do |command, _msg|
          script = script_of command
          expect(script).to include 'rvm ruby-3.4.13 do gem install bundler -v 2.5.4'
          expect(script).to include 'cd /var/www/rails/current && /usr/local/rvm/bin/rvm ruby-3.4.13 do bundle check'
          expect(script).to include 'rvm alias create default ruby-3.4.13'
          expect(script).to include "passenger_ruby"
          expect(script).to include "/usr/local/rvm/rubies/ruby-3.4.13/bin/ruby;#'"
          expect(script).to include "nginx -t\n  systemctl reload nginx"
          expect(script).to include 'systemctl try-restart delayed_jobs@default.service'
          expect(script).to include 'systemctl try-restart rake-index.service'
          expect(script.index('bundle check')).to be < script.index('alias create default')
          'ok'
        end
      end

      counts = subject.patch! [guest, other], dry_run: false
      expect(counts).to eq(patched: 2, current: 0, failed: 0)
      expect(out.string).to include 'compiling ruby-3.4.13 in api @ host-a'
    end

    it 'reuses a cached archive, uploads it to a host that lacks it, and reports a failed switch with the rollback' do
      File.write File.join(local_dir, archive), 'tgz'
      expect(guest).to receive(:exec).with(/passenger_ruby/).and_return [true, old_inventory]
      expect(guest).not_to receive(:exec!).with(anything, /rvm install/)
      expect(host).to receive(:exec).with("test -f /tmp/#{archive}").and_return [false, '']
      expect(sftp).to receive(:upload!).with("#{local_dir}/#{archive}", "/tmp/#{archive}")
      expect(host).to receive(:exec!).with(%r{tar -C /usr/local/rvm -xzf}, /unpacking/)
      expect(guest).to receive(:exec!).with(/\Abash -c /, /switching/).and_raise "switching web to ruby-3.4.13 failed:\n\nbundle check failed in /var/www/rails/current"

      counts = subject.patch! [guest], dry_run: false
      expect(counts).to eq(patched: 0, current: 0, failed: 1)
      expect(out.string).to include 'archive cached'
      expect(out.string).to match %r{FAILED\e\[39m \(bundle check failed in /var/www/rails/current\)}
      expect(out.string).to include 'rvm alias create default ruby-3.4.8'
    end
  end
end
