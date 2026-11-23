require 'spec_helper'

describe CloudModel::Workers::Mixins::RubyLayout do
  let(:host) { double CloudModel::Host, name: 'core-a' }
  let(:worker_class) do
    Class.new(CloudModel::Workers::BaseWorker) do
      include CloudModel::Workers::Mixins::RubyLayout
    end
  end
  subject { worker_class.new host }
  let(:rootfs) { '/var/lib/cloudmodel/deploy/web-1/rootfs' }

  before do
    allow(subject).to receive(:render_to_remote)
    allow(subject).to receive(:mkdir_p)
    allow(host).to receive(:exec!)
    allow(host).to receive(:exec).and_return [true, '']
    allow(CloudModel::RubyRelease).to receive(:versions_on).with(host, 'debian-12', 'amd64').and_return %w(3.4.11 3.4.13 4.0.1)
    allow(host).to receive(:exec).with("ls -1 /cloud/ruby/debian-12-amd64/ruby-*/bin/ 2>/dev/null").and_return [true, "/cloud/ruby/debian-12-amd64/ruby-3.4.13/bin/:\nbundle\nerb\ngem\nirb\nrake\nruby\n\n/cloud/ruby/debian-12-amd64/ruby-4.0.1/bin/:\nbundle\ngem\nruby\n"]
    allow(host).to receive(:exec).with(/awk -F: .*www/).and_return [true, "33\n"]
  end

  describe '#write_ruby_layout' do
    it 'writes shims for every program of every release, points current at the newest release of the default line, the default line into /etc/ruby-version, profile.d and the gem homes' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/support/ruby/shim.sh', "#{rootfs}/usr/local/ruby/bin/.shim", 0755)
      expect(host).to receive(:exec!).with(%r{cd #{rootfs}/usr/local/ruby/bin && for p in bundle erb gem irb rake ruby; do ln -sfn \.shim "\$p"; done}, anything)
      expect(host).to receive(:exec!).with("ln -sfn /opt/ruby/ruby-3.4.13 #{rootfs}/usr/local/ruby/current", anything)
      expect(host).to receive(:exec!).with("printf '%s\\n' 3.4 > #{rootfs}/etc/ruby-version", anything)
      expect(subject).to receive(:render_to_remote).with('/cloud_model/support/ruby/profile_ruby.sh', "#{rootfs}/etc/profile.d/ruby.sh", 0644)
      expect(host).to receive(:exec!).with("chown 0:33 #{rootfs}/var/lib/gems/3.4.0 && chmod 2775 #{rootfs}/var/lib/gems/3.4.0", anything)
      expect(host).to receive(:exec!).with("chown 0:33 #{rootfs}/var/lib/gems/4.0.0 && chmod 2775 #{rootfs}/var/lib/gems/4.0.0", anything)

      expect(subject.write_ruby_layout(rootfs, os_version: 'debian-12', arch: 'amd64', default_line: '3.4', lines: %w(3.4 4.0))).to eq '3.4.13'
    end

    it 'pins current to an installed full version and leaves the gem home to root where the rootfs has no www group' do
      allow(host).to receive(:exec).with(/awk -F: .*www/).and_return [true, '']
      expect(host).to receive(:exec!).with("ln -sfn /opt/ruby/ruby-3.4.11 #{rootfs}/usr/local/ruby/current", anything)
      expect(host).to receive(:exec!).with("chown 0:0 #{rootfs}/var/lib/gems/3.4.0 && chmod 2775 #{rootfs}/var/lib/gems/3.4.0", anything)
      expect(subject.write_ruby_layout(rootfs, os_version: 'debian-12', arch: 'amd64', default_line: '3.4.11')).to eq '3.4.11'
    end

    it 'fails with the missing line when the host has no release of it' do
      expect { subject.write_ruby_layout(rootfs, os_version: 'debian-12', arch: 'amd64', default_line: '3.3') }.to raise_error(/no Ruby release of line 3.3 for debian-12 amd64 on core-a \(has: 3.4.11 3.4.13 4.0.1\)/)
      expect { subject.write_ruby_layout(rootfs, os_version: 'debian-12', arch: 'amd64', default_line: '3.4', lines: %w(3.4 3.2)) }.to raise_error(/no Ruby release of line 3.2/)
    end

    it 'disables a leftover RVM profile hook so it cannot shadow the shims' do
      expect(host).to receive(:exec).with(/test -f .*profile.d\/rvm.sh && mv -f .*rvm.sh .*rvm.sh.disabled/)
      subject.write_ruby_layout(rootfs, os_version: 'debian-12', arch: 'amd64', default_line: '3.4')
    end
  end

  describe '#bind_ruby_dataset / #unbind_ruby_dataset' do
    it 'bind-mounts the host dataset read-only at <rootfs>/opt/ruby once, and unmounts it' do
      allow(host).to receive(:mounted_at?).with("#{rootfs}/opt/ruby").and_return false, true, true
      expect(host).to receive(:exec!).with("mount --bind -o ro /cloud/ruby/debian-12-amd64 #{rootfs}/opt/ruby", anything).once
      subject.bind_ruby_dataset rootfs, os_version: 'debian-12', arch: 'amd64'
      subject.bind_ruby_dataset rootfs, os_version: 'debian-12', arch: 'amd64'
      expect(host).to receive(:exec!).with("umount #{rootfs}/opt/ruby", anything)
      subject.unbind_ruby_dataset rootfs
    end
  end
end
