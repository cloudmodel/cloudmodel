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

  describe '.pair' do
    it 'is an ed25519 pair at the configured path, marked with the sync comment' do
      pair = described_class.pair
      expect(pair.private_key_file).to eq key_file
      expect(pair.type).to eq 'ed25519'
      expect(pair.comment).to eq 'cloudmodel-zfs-sync'
    end
  end

  describe '.ensure!' do
    it 'generates the pair when missing' do
      expect_any_instance_of(CloudModel::SshKeyPair).to receive(:local_exec!).with(
        "ssh-keygen -q -N '' -t ed25519 -C cloudmodel-zfs-sync -f #{key_file}", "Failed to generate SSH key pair #{key_file}"
      ) do
        FileUtils.mkdir_p File.dirname(key_file)
        File.write key_file, 'private'
        File.write "#{key_file}.pub", 'ssh-ed25519 AAAA cloudmodel-zfs-sync'
      end

      expect(described_class.present?).to eq false
      expect(described_class.ensure!).to eq true
      expect(described_class.present?).to eq true
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
