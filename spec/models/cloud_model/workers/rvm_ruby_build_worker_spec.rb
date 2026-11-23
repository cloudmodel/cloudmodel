require 'spec_helper'

describe CloudModel::Workers::RvmRubyBuildWorker do
  let(:host) { double CloudModel::Host, name: 'build-host', arch: 'amd64' }
  let(:template) { double CloudModel::GuestTemplate, id: 'tpl1', build_dataset: 'guests/build/type1/tpl1' }
  let(:volume) { double CloudModel::BuildZfsVolume, dataset_name: 'guests/build/ruby/3.4.13/debian-12-amd64', mountpoint: '/cloud/build/ruby/3.4.13/debian-12-amd64' }
  let(:buildenv) { double 'buildenv', rootfs_path: '/cloud/build/ruby/3.4.13/debian-12-amd64-buildenv/rootfs' }

  subject { described_class.new host, template: template, version: '3.4.13', volume: volume }

  before do
    allow(CloudModel::BuildZfsVolume).to receive(:new).with(host, 'guests/build/ruby/3.4.13/debian-12-amd64-buildenv', mountpoint: '/cloud/build/ruby/3.4.13/debian-12-amd64-buildenv').and_return buildenv
  end

  it 'clones the template, installs the ruby with rvm in the chroot, copies it into the ruby volume, commits and destroys the clone' do
    expect(template).to receive(:ensure_build_volume!).with(host).ordered
    expect(buildenv).to receive(:prepare_from!).with('guests/build/type1/tpl1').ordered
    expect(host).to receive(:exec!).with(%r{cp /etc/resolv.conf /cloud/build/ruby/3.4.13/debian-12-amd64-buildenv/rootfs/etc/resolv.conf}, anything).ordered
    expect(subject).to receive(:chroot!).with(buildenv.rootfs_path, /rvm install ruby-3.4.13 --disable-binary --autolibs=read-fail\ntest -x \/usr\/local\/rvm\/rubies\/ruby-3.4.13\/bin\/ruby/, /rvm install/).ordered
    expect(volume).to receive(:prepare!).ordered
    expect(host).to receive(:exec!).with("cd #{buildenv.rootfs_path}/usr/local/rvm && cp -a --parents rubies/ruby-3.4.13 gems/ruby-3.4.13* environments/ruby-3.4.13* wrappers/ruby-3.4.13* /cloud/build/ruby/3.4.13/debian-12-amd64/", /copying/).ordered
    expect(volume).to receive(:commit!).ordered
    expect(subject).to receive(:cleanup_chroot_quietly).with(buildenv.rootfs_path).ordered
    expect(buildenv).to receive(:destroy!).ordered

    expect(subject.build!).to eq volume
  end

  it 'destroys the clone even when the install fails, and lets the error through' do
    allow(template).to receive(:ensure_build_volume!)
    allow(buildenv).to receive(:prepare_from!)
    allow(host).to receive(:exec!).with(/resolv.conf/, anything)
    expect(subject).to receive(:chroot!).and_raise 'rvm install ruby-3.4.13 failed on build-host'
    expect(volume).not_to receive(:prepare!)
    expect(subject).to receive(:cleanup_chroot_quietly)
    expect(buildenv).to receive(:destroy!)

    expect { subject.build! }.to raise_error(/rvm install ruby-3.4.13 failed/)
  end

  it 'refreshes rvm first when asked' do
    expect(described_class.new(host, template: template, version: '3.4.13', volume: volume, rvm_update: true).build_script).to start_with "set -e\n/usr/local/rvm/bin/rvm get master\n"
    expect(subject.build_script).not_to include 'rvm get master'
  end
end
