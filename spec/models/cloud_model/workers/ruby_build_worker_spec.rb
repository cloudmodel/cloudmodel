require 'spec_helper'

describe CloudModel::Workers::RubyBuildWorker do
  let(:host) { double CloudModel::Host, name: 'build-host', arch: 'amd64' }
  let(:template) { double CloudModel::GuestTemplate, id: 'tpl1', build_dataset: 'guests/build/type1/tpl1' }
  let(:volume) { double CloudModel::BuildZfsVolume, rootfs_path: '/cloud/build/ruby/3.4.13/tpl1/rootfs' }

  subject { described_class.new host, template: template, version: '3.4.13' }

  before do
    allow(CloudModel::BuildZfsVolume).to receive(:new).with(host, 'guests/build/ruby/3.4.13/tpl1', mountpoint: '/cloud/build/ruby/3.4.13/tpl1').and_return volume
    allow(CloudModel.config).to receive(:build_dataset).and_return 'guests/build'
  end

  it 'clones the template, installs the ruby with rvm in the chroot, packs it and destroys the clone' do
    expect(template).to receive(:ensure_build_volume!).with(host).ordered
    expect(volume).to receive(:prepare_from!).with('guests/build/type1/tpl1').ordered
    expect(host).to receive(:exec!).with(%r{cp /etc/resolv.conf /cloud/build/ruby/3.4.13/tpl1/rootfs/etc/resolv.conf}, anything).ordered
    expect(subject).to receive(:chroot!).with('/cloud/build/ruby/3.4.13/tpl1/rootfs', /rvm install ruby-3.4.13 --disable-binary --autolibs=read-fail\ntest -x \/usr\/local\/rvm\/rubies\/ruby-3.4.13\/bin\/ruby/, /rvm install/).ordered
    expect(host).to receive(:exec!).with("cd /cloud/build/ruby/3.4.13/tpl1/rootfs/usr/local/rvm && tar -cf - rubies/ruby-3.4.13 gems/ruby-3.4.13* environments/ruby-3.4.13* wrappers/ruby-3.4.13* | gzip -1 > /tmp/ruby.tar.gz", /packing/).ordered
    expect(subject).to receive(:cleanup_chroot_quietly).with('/cloud/build/ruby/3.4.13/tpl1/rootfs').ordered
    expect(volume).to receive(:destroy!).ordered

    expect(subject.build!('/tmp/ruby.tar.gz')).to eq '/tmp/ruby.tar.gz'
  end

  it 'destroys the clone even when the install fails, and lets the error through' do
    allow(template).to receive(:ensure_build_volume!)
    allow(volume).to receive(:prepare_from!)
    allow(host).to receive(:exec!).with(/resolv.conf/, anything)
    expect(subject).to receive(:chroot!).and_raise 'rvm install ruby-3.4.13 failed on build-host'
    expect(subject).to receive(:cleanup_chroot_quietly)
    expect(volume).to receive(:destroy!)

    expect { subject.build! '/tmp/ruby.tar.gz' }.to raise_error(/rvm install ruby-3.4.13 failed/)
  end

  it 'refreshes rvm first when asked' do
    expect(described_class.new(host, template: template, version: '3.4.13', rvm_update: true).build_script).to start_with "set -e\n/usr/local/rvm/bin/rvm get master\n"
    expect(subject.build_script).not_to include 'rvm get master'
  end
end
