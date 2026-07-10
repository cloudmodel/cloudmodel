# encoding: UTF-8

require 'spec_helper'

describe CloudModel::BuildZfsVolume do
  let(:host) { double CloudModel::Host }
  subject { CloudModel::BuildZfsVolume.new host, 'guests/build/core/tpl1', mountpoint: '/cloud/build/core/tpl1' }

  def stub_dataset_exists exists
    allow(host).to receive(:exec).with('zfs list guests/build/core/tpl1').and_return([exists, ''])
  end

  def stub_snapshot_exists dataset, exists
    allow(host).to receive(:exec).with("zfs list -t snapshot #{dataset}@ready").and_return([exists, ''])
  end

  def stub_mounted mounted
    allow(host).to receive(:exec).with('zfs get -H -o value mounted guests/build/core/tpl1').and_return([true, mounted ? "yes\n" : "no\n"])
  end

  describe 'accessors' do
    it 'should expose host, dataset_name and mountpoint' do
      expect(subject.host).to eq host
      expect(subject.dataset_name).to eq 'guests/build/core/tpl1'
      expect(subject.mountpoint).to eq '/cloud/build/core/tpl1'
    end
  end

  describe 'ready_snapshot' do
    it 'should append the ready snapshot name to the dataset' do
      expect(subject.ready_snapshot).to eq 'guests/build/core/tpl1@ready'
    end
  end

  describe 'prepare!' do
    it 'should create the dataset with mountpoint and mark it building' do
      stub_dataset_exists false
      expect(host).to receive(:exec!).with('zfs create -p -o mountpoint=/cloud/build/core/tpl1 guests/build/core/tpl1', /ZFS command failed/)
      expect(host).to receive(:exec!).with('zfs set com.cloudmodel:status=building guests/build/core/tpl1', /ZFS command failed/)

      subject.prepare!
    end

    it 'should destroy a leftover dataset first' do
      stub_dataset_exists true
      stub_mounted false
      expect(host).to receive(:exec!).with('zfs destroy -r guests/build/core/tpl1', /ZFS command failed/).ordered
      expect(host).to receive(:exec!).with(/zfs create/, /ZFS command failed/).ordered
      allow(host).to receive(:exec!).with(/zfs set/, anything)

      subject.prepare!
    end
  end

  describe 'prepare_from!' do
    it 'should clone the source ready snapshot and mark it building' do
      stub_snapshot_exists 'guests/build/core/src', true
      stub_dataset_exists false
      expect(host).to receive(:exec!).with('zfs clone -p -o mountpoint=/cloud/build/core/tpl1 guests/build/core/src@ready guests/build/core/tpl1', /ZFS command failed/)
      expect(host).to receive(:exec!).with('zfs set com.cloudmodel:status=building guests/build/core/tpl1', /ZFS command failed/)

      subject.prepare_from! 'guests/build/core/src'
    end

    it 'should raise if the source snapshot does not exist' do
      stub_snapshot_exists 'guests/build/core/src', false

      expect { subject.prepare_from! 'guests/build/core/src' }.to raise_error(/guests\/build\/core\/src@ready does not exist/)
    end
  end

  describe 'commit!' do
    it 'should snapshot the dataset and mark it ready' do
      stub_snapshot_exists 'guests/build/core/tpl1', false
      expect(host).to receive(:exec!).with('zfs snapshot guests/build/core/tpl1@ready', /ZFS command failed/)
      expect(host).to receive(:exec!).with('zfs set com.cloudmodel:status=ready guests/build/core/tpl1', /ZFS command failed/)

      subject.commit!
    end

    it 'should replace an existing ready snapshot' do
      stub_snapshot_exists 'guests/build/core/tpl1', true
      expect(host).to receive(:exec!).with('zfs destroy guests/build/core/tpl1@ready', /ZFS command failed/).ordered
      expect(host).to receive(:exec!).with('zfs snapshot guests/build/core/tpl1@ready', /ZFS command failed/).ordered
      allow(host).to receive(:exec!).with(/zfs set/, anything)

      subject.commit!
    end
  end

  describe 'ready?' do
    it 'should be true when the ready snapshot exists' do
      stub_snapshot_exists 'guests/build/core/tpl1', true

      expect(subject.ready?).to eq true
    end

    it 'should be false when the ready snapshot (or its dataset) is missing' do
      stub_snapshot_exists 'guests/build/core/tpl1', false

      expect(subject.ready?).to eq false
    end
  end

  describe 'rootfs_path' do
    it 'should return the rootfs inside the volume' do
      expect(subject.rootfs_path).to eq '/cloud/build/core/tpl1/rootfs'
    end
  end

  describe '.ready_snapshot' do
    it 'should return the ready snapshot for a dataset' do
      expect(CloudModel::BuildZfsVolume.ready_snapshot('guests/build/core/xy')).to eq 'guests/build/core/xy@ready'
    end
  end

  describe 'scrub_identity!' do
    it 'should remove ssh host keys and reset the machine id in the rootfs' do
      expect(host).to receive(:exec!).with('rm -f /cloud/build/core/tpl1/rootfs/etc/ssh/ssh_host_*', /ZFS command failed/)
      expect(host).to receive(:exec!).with('rm -f /cloud/build/core/tpl1/rootfs/etc/machine-id /cloud/build/core/tpl1/rootfs/var/lib/dbus/machine-id && touch /cloud/build/core/tpl1/rootfs/etc/machine-id', /ZFS command failed/)

      subject.scrub_identity!
    end
  end

  describe 'fail!' do
    it 'should mark an existing dataset as failed' do
      stub_dataset_exists true
      expect(host).to receive(:exec!).with('zfs set com.cloudmodel:status=failed guests/build/core/tpl1', /ZFS command failed/)

      subject.fail!
    end

    it 'should do nothing without a dataset' do
      stub_dataset_exists false
      expect(host).not_to receive(:exec!)

      subject.fail!
    end
  end

  describe 'destroy!' do
    it 'should recursively unmount (clearing stray chroot binds) and destroy the dataset' do
      stub_dataset_exists true
      stub_mounted true
      expect(host).to receive(:exec).with('umount -R /cloud/build/core/tpl1')
      expect(host).to receive(:exec!).with('zfs destroy -r guests/build/core/tpl1', /ZFS command failed/)

      subject.destroy!
    end

    it 'should not umount when not mounted' do
      stub_dataset_exists true
      stub_mounted false
      expect(host).not_to receive(:exec).with(/umount/)
      expect(host).to receive(:exec!).with('zfs destroy -r guests/build/core/tpl1', /ZFS command failed/)

      subject.destroy!
    end

    it 'should do nothing without a dataset' do
      stub_dataset_exists false
      expect(host).not_to receive(:exec!)

      subject.destroy!
    end
  end

  describe 'mount!' do
    it 'should mount when not mounted' do
      stub_mounted false
      expect(host).to receive(:exec!).with('zfs mount guests/build/core/tpl1', /ZFS command failed/)

      subject.mount!
    end

    it 'should not mount when already mounted' do
      stub_mounted true
      expect(host).not_to receive(:exec!)

      subject.mount!
    end
  end

  describe 'unmount!' do
    it 'should unmount when mounted' do
      stub_mounted true
      expect(host).to receive(:exec!).with('zfs unmount guests/build/core/tpl1', /ZFS command failed/)

      subject.unmount!
    end

    it 'should not unmount when not mounted' do
      stub_mounted false
      expect(host).not_to receive(:exec!)

      subject.unmount!
    end
  end

  describe 'mounted?' do
    it 'should be true when zfs reports mounted' do
      stub_mounted true
      expect(subject.mounted?).to eq true
    end

    it 'should be false when the mounted query fails' do
      allow(host).to receive(:exec).with('zfs get -H -o value mounted guests/build/core/tpl1').and_return([false, 'dataset does not exist'])
      expect(subject.mounted?).to eq false
    end
  end
end
