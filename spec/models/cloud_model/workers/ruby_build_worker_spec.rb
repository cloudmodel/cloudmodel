require 'spec_helper'

describe CloudModel::Workers::RubyBuildWorker do
  let(:host) { double CloudModel::Host, name: 'build-host', arch: 'amd64' }
  let(:release) { CloudModel::RubyRelease.new version: '3.4.13', os_version: 'debian-12', arch: 'amd64' }
  let(:core) { double CloudModel::GuestCoreTemplate, id: 'core1', build_dataset: 'guests/build/core/core1' }
  let(:buildenv) { double 'buildenv', rootfs_path: '/cloud/build/ruby-build/ruby-3.4.13-debian-12-amd64/rootfs' }
  let(:index) { { '3.4.13' => { url: 'https://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.13.tar.xz', sha256: 'a' * 64 } } }

  subject { described_class.new host, release: release, index: index }

  before do
    allow(CloudModel::BuildZfsVolume).to receive(:new).with(host, 'guests/build/ruby-build/ruby-3.4.13-debian-12-amd64', mountpoint: '/cloud/build/ruby-build/ruby-3.4.13-debian-12-amd64').and_return buildenv
    allow(CloudModel::GuestCoreTemplate).to receive(:where).and_return double(order: double(first: core))
    allow(core).to receive(:respond_to?).with(:ensure_build_volume!).and_return true
  end

  it 'builds from the checked tarball with the final prefix in a clone of the core template, copies the result into the host dataset and destroys the clone' do
    expect(core).to receive(:ensure_build_volume!).with(host).ordered
    expect(release).to receive(:ensure_dataset_on!).with(host).ordered
    expect(buildenv).to receive(:prepare_from!).with('guests/build/core/core1').ordered
    expect(host).to receive(:exec!).with(%r{cp /etc/resolv.conf .*ruby-3.4.13-debian-12-amd64/rootfs/etc/resolv.conf}, anything).ordered
    expect(subject).to receive(:chroot!).with(buildenv.rootfs_path, /curl -fsSL -o ruby.tar.xz https:\/\/cache.ruby-lang.org\/pub\/ruby\/3.4\/ruby-3.4.13.tar.xz\necho #{'a' * 64}\\ \\ ruby.tar.xz \| sha256sum -c -\n.*configure --prefix=\/opt\/ruby\/ruby-3.4.13 --enable-shared --enable-load-relative/m, /building ruby-3.4.13 failed/).ordered
    expect(host).to receive(:exec!).with("rm -rf /cloud/ruby/debian-12-amd64/ruby-3.4.13 && cp -a #{buildenv.rootfs_path}/opt/ruby/ruby-3.4.13 /cloud/ruby/debian-12-amd64/ruby-3.4.13", /copying/).ordered
    expect(host).to receive(:exec!).with('test -x /cloud/ruby/debian-12-amd64/ruby-3.4.13/bin/ruby', anything).ordered
    expect(subject).to receive(:cleanup_chroot_quietly).with(buildenv.rootfs_path).ordered
    expect(buildenv).to receive(:destroy!).ordered

    expect(subject.build!).to eq release
  end

  it 'destroys the clone even when the build fails, and lets the error through' do
    allow(core).to receive(:ensure_build_volume!)
    allow(release).to receive(:ensure_dataset_on!)
    allow(buildenv).to receive(:prepare_from!)
    allow(host).to receive(:exec!).with(/resolv.conf/, anything)
    expect(subject).to receive(:chroot!).and_raise 'building ruby-3.4.13 failed on build-host'
    expect(host).not_to receive(:exec!).with(/cp -a/, anything)
    expect(subject).to receive(:cleanup_chroot_quietly)
    expect(buildenv).to receive(:destroy!)

    expect { subject.build! }.to raise_error(/building ruby-3.4.13 failed/)
  end

  it 'refuses a release the index does not know' do
    worker = described_class.new host, release: release, index: {}
    expect { worker.build_script }.to raise_error(/not in the release index/)
  end

  it 'checks the built interpreter loads openssl, yaml, zlib and readline' do
    expect(subject.build_script).to include "/opt/ruby/ruby-3.4.13/bin/ruby -ropenssl -ryaml -rzlib -rreadline -e 'print RUBY_VERSION' | grep -qx 3.4.13"
  end
end
