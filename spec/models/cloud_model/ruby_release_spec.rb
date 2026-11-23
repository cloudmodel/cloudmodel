require 'spec_helper'

describe CloudModel::RubyRelease do
  let(:host) { double CloudModel::Host, name: 'core-a' }
  let(:build_host) { double CloudModel::Host, name: 'build-host' }
  subject { described_class.new version: '3.4.13', os_version: 'debian-12', arch: 'amd64' }

  it 'refuses anything but a full version' do
    expect { described_class.new version: '3.4', os_version: 'debian-12', arch: 'amd64' }.to raise_error ArgumentError
  end

  it 'names dataset, mountpoint, directory and snapshot per os/arch and release' do
    expect(subject.dataset).to eq 'guests/ruby/debian-12-amd64'
    expect(subject.mountpoint).to eq '/cloud/ruby/debian-12-amd64'
    expect(subject.dir).to eq '/cloud/ruby/debian-12-amd64/ruby-3.4.13'
    expect(subject.guest_dir).to eq '/opt/ruby/ruby-3.4.13'
    expect(subject.snapshot).to eq 'guests/ruby/debian-12-amd64@ruby-3.4.13'
    expect(subject.line).to eq '3.4'
    expect(subject.abi).to eq '3.4.0'
  end

  describe '.line_of / .abi_of / .newest / .resolve' do
    it 'resolves lines and versions against what is installed' do
      versions = %w(3.4.11 3.4.13 4.0.1)
      expect(described_class.line_of('3.4.13')).to eq '3.4'
      expect(described_class.abi_of('4.0.1')).to eq '4.0.0'
      expect(described_class.newest('3.4', versions)).to eq '3.4.13'
      expect(described_class.newest('3.3', versions)).to be_nil
      expect(described_class.resolve('3.4', versions)).to eq '3.4.13'
      expect(described_class.resolve('3.4.11', versions)).to eq '3.4.11'   # installed: a pin
      expect(described_class.resolve('3.4.8', versions)).to eq '3.4.13'    # not installed: its line
      expect(described_class.resolve('3.3.9', versions)).to be_nil
    end
  end

  describe '.versions_on' do
    it 'lists the release directories of the host dataset, newest last' do
      expect(host).to receive(:exec).with("ls -1 /cloud/ruby/debian-12-amd64 2>/dev/null").and_return [true, "ruby-3.4.13\nruby-3.4.9\nlost+found\n"]
      expect(described_class.versions_on(host, 'debian-12', 'amd64')).to eq %w(3.4.9 3.4.13)
    end

    it 'is empty without the dataset' do
      allow(host).to receive(:exec).and_return [false, '']
      expect(described_class.versions_on(host, 'debian-12', 'amd64')).to eq []
    end
  end

  describe '.index' do
    it 'parses the release index into version → tar.xz url and sha256, releases only' do
      body = <<~TXT
        name\turl\tsha1\tsha256\tsha512
        ruby-3.4.13\thttps://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.13.tar.gz\t#{'1' * 40}\t#{'b' * 64}\t#{'c' * 128}
        ruby-3.4.13\thttps://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.13.tar.xz\t#{'1' * 40}\t#{'a' * 64}\t#{'c' * 128}
        ruby-3.5.0-preview1\thttps://cache.ruby-lang.org/pub/ruby/3.5/ruby-3.5.0-preview1.tar.xz\t#{'1' * 40}\t#{'d' * 64}\t#{'c' * 128}
      TXT
      allow(Net::HTTP).to receive(:get).with(URI(described_class::INDEX_URL)).and_return body
      index = described_class.index
      expect(index).to eq '3.4.13' => { url: 'https://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.13.tar.xz', sha256: 'a' * 64 }
      expect(described_class.newest_in_index(['3.4', '3.3'], index)).to eq '3.4' => '3.4.13'
    end
  end

  describe '#ensure_dataset_on!' do
    it 'creates the dataset when missing' do
      allow(host).to receive(:exec).with('zfs list -H -o name guests/ruby/debian-12-amd64').and_return [false, '']
      expect(host).to receive(:exec!).with('zfs create -p -o mountpoint=/cloud/ruby/debian-12-amd64 guests/ruby/debian-12-amd64', anything)
      subject.ensure_dataset_on! host
    end

    it 'mounts an existing unmounted dataset and leaves a mounted one alone' do
      allow(host).to receive(:exec).with('zfs list -H -o name guests/ruby/debian-12-amd64').and_return [true, '']
      allow(host).to receive(:exec).with('zfs get -H -o value mounted guests/ruby/debian-12-amd64').and_return [true, "no\n"], [true, "yes\n"]
      expect(host).to receive(:exec!).with('zfs mount guests/ruby/debian-12-amd64', anything).once
      subject.ensure_dataset_on! host
      subject.ensure_dataset_on! host
    end
  end

  describe '#ensure_on!' do
    before { allow(CloudModel::Host).to receive(:build_host).with('amd64').and_return build_host }

    it 'does nothing when the release is on the host' do
      expect(host).to receive(:exec).with('test -x /cloud/ruby/debian-12-amd64/ruby-3.4.13/bin/ruby').and_return [true, '']
      expect(subject).not_to receive(:sync_zfs_dataset!)
      subject.ensure_on! host, output: StringIO.new
    end

    it 'builds on the build host when nobody has it, snapshots, syncs the snapshot and mounts' do
      allow(host).to receive(:exec).with('test -x /cloud/ruby/debian-12-amd64/ruby-3.4.13/bin/ruby').and_return [false, ''], [true, '']
      allow(build_host).to receive(:exec).with('test -x /cloud/ruby/debian-12-amd64/ruby-3.4.13/bin/ruby').and_return [false, '']
      allow(build_host).to receive(:exec).with('zfs list -H -t snapshot -o name guests/ruby/debian-12-amd64@ruby-3.4.13').and_return [false, '']
      worker = double 'worker'
      expect(CloudModel::Workers::RubyBuildWorker).to receive(:new).with(build_host, release: subject).and_return worker
      expect(worker).to receive(:build!).ordered
      expect(build_host).to receive(:exec!).with('zfs snapshot guests/ruby/debian-12-amd64@ruby-3.4.13', anything).ordered
      expect(subject).to receive(:sync_zfs_dataset!).with(build_host, host, 'guests/ruby/debian-12-amd64', snapshot: 'guests/ruby/debian-12-amd64@ruby-3.4.13').ordered
      allow(host).to receive(:exec).with('zfs list -H -o name guests/ruby/debian-12-amd64').and_return [true, '']
      allow(host).to receive(:exec).with('zfs get -H -o value mounted guests/ruby/debian-12-amd64').and_return [true, "no\n"]
      expect(host).to receive(:exec!).with('zfs mount guests/ruby/debian-12-amd64', anything).ordered
      subject.ensure_on! host, output: StringIO.new
    end

    it 'only syncs when the build host has the release already' do
      allow(host).to receive(:exec).with(/test -x/).and_return [false, ''], [true, '']
      allow(host).to receive(:exec).with(/zfs (list|get)/).and_return [true, "yes\n"]
      allow(build_host).to receive(:exec).with(/test -x/).and_return [true, '']
      allow(build_host).to receive(:exec).with(/zfs list -H -t snapshot/).and_return [true, '']
      expect(CloudModel::Workers::RubyBuildWorker).not_to receive(:new)
      expect(subject).to receive(:sync_zfs_dataset!)
      allow(host).to receive(:exec!)
      subject.ensure_on! host, output: StringIO.new
    end

    it 'fails loudly when the release is not there after the sync' do
      allow(host).to receive(:exec).with(/test -x/).and_return [false, '']
      allow(host).to receive(:exec).with(/zfs (list|get)/).and_return [true, "yes\n"]
      allow(build_host).to receive(:exec).and_return [true, '']
      allow(subject).to receive(:sync_zfs_dataset!)
      allow(host).to receive(:exec!)
      expect { subject.ensure_on! host, output: StringIO.new }.to raise_error(/not on core-a after the sync/)
    end
  end
end
