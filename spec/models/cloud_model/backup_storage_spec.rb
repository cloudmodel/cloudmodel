# encoding: UTF-8

require 'spec_helper'

describe CloudModel::BackupStorage do
  describe '.status' do
    it 'prefers ZFS stats (including quota and snapshot subtree) over df' do
      backup_host = double 'backup_host'
      allow(CloudModel::Host).to receive(:local).and_return backup_host
      allow(CloudModel::LxdCustomVolume).to receive(:backup_root_dataset).and_return 'data/bk'
      allow(backup_host).to receive(:exec).with(/\Azfs get -Hp -o property,value/).and_return(
        [true, "used\t60\navailable\t40\nquota\t100\n"]
      )
      allow(backup_host).to receive(:exec).with('zfs get -Hp -o value used data/bk/zfs_backups').and_return([true, "25\n"])
      allow(described_class).to receive(:dump_tree_bytes).and_return 30

      expect(described_class.status).to eq(
        size_bytes: 100, used_bytes: 60, available_bytes: 40,
        usage_percent: 60.0, snapshots_bytes: 25, dumps_bytes: 30
      )
    end

    it 'derives the size from used + available without a quota' do
      backup_host = double 'backup_host'
      allow(CloudModel::Host).to receive(:local).and_return backup_host
      allow(CloudModel::LxdCustomVolume).to receive(:backup_root_dataset).and_return 'data/bk'
      allow(backup_host).to receive(:exec).with(/\Azfs get -Hp -o property,value/).and_return(
        [true, "used\t75\navailable\t25\nquota\t0\n"]
      )
      allow(backup_host).to receive(:exec).with(/zfs_backups/).and_return([false, ''])
      allow(described_class).to receive(:dump_tree_bytes).and_return 0

      expect(described_class.status).to include size_bytes: 100, usage_percent: 75.0, snapshots_bytes: 0
    end

    it 'falls back to df when the backup dir is not on ZFS' do
      allow(CloudModel::LxdCustomVolume).to receive(:backup_root_dataset).and_return nil
      allow(CloudModel.config).to receive(:backup_directory).and_return '/backups'
      allow(described_class).to receive(:`).with(/\Adf -kP /).and_return(
        "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 100 60 40 60% /backups\n"
      )
      allow(described_class).to receive(:dump_tree_bytes).and_return 7 * 1024

      expect(described_class.status).to eq(
        size_bytes: 100 * 1024, used_bytes: 60 * 1024, available_bytes: 40 * 1024,
        usage_percent: 60.0, snapshots_bytes: nil, dumps_bytes: 7 * 1024
      )
    end

    it 'is nil when neither source is available' do
      allow(CloudModel::LxdCustomVolume).to receive(:backup_root_dataset).and_return nil
      allow(described_class).to receive(:`).with(/\Adf -kP /).and_return ''

      expect(described_class.status).to be_nil
    end
  end
end
