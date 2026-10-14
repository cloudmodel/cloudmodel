# encoding: UTF-8

require 'spec_helper'
require 'tmpdir'

describe CloudModel::ZfsSyncKey do
  let(:dir) { Dir.mktmpdir 'zfs_sync_key' }
  let(:key_file) { "#{dir}/keys/zfs_sync" }

  before do
    allow(CloudModel.config).to receive(:zfs_sync_key_file).and_return(key_file)
  end

  after do
    FileUtils.rm_rf dir
  end

  describe '.present?' do
    it 'needs both halves of the pair' do
      expect(described_class.present?).to eq false
      FileUtils.mkdir_p File.dirname(key_file)
      File.write key_file, 'private'
      expect(described_class.present?).to eq false
      File.write "#{key_file}.pub", 'ssh-ed25519 AAAA cloudmodel-zfs-sync'
      expect(described_class.present?).to eq true
    end
  end

  describe '.ensure!' do
    it 'generates an ed25519 pair with the marker comment when missing' do
      expect(described_class).to receive(:local_exec!).with(
        "ssh-keygen -q -N '' -t ed25519 -C cloudmodel-zfs-sync -f #{key_file}", 'Failed to generate the ZFS sync key pair'
      ) do
        FileUtils.mkdir_p File.dirname(key_file)
        File.write key_file, 'private'
        File.write "#{key_file}.pub", 'ssh-ed25519 AAAA cloudmodel-zfs-sync'
      end

      expect(described_class.ensure!).to eq true
      expect(File.stat(key_file).mode & 0777).to eq 0600
    end

    it 'leaves an existing pair alone' do
      FileUtils.mkdir_p File.dirname(key_file)
      File.write key_file, 'private'
      File.write "#{key_file}.pub", 'ssh-ed25519 AAAA cloudmodel-zfs-sync'

      expect(described_class).not_to receive(:local_exec!)
      expect(described_class.ensure!).to eq true
    end
  end

  describe '.authorized_keys_line' do
    it 'binds the public key to the receive-only forced command without pty or forwarding' do
      FileUtils.mkdir_p File.dirname(key_file)
      File.write "#{key_file}.pub", "ssh-ed25519 AAAA cloudmodel-zfs-sync\n"

      expect(described_class.authorized_keys_line).to eq 'restrict,command="/usr/local/sbin/zfs-receive-only" ssh-ed25519 AAAA cloudmodel-zfs-sync'
    end
  end
end
