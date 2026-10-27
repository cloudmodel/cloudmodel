# encoding: UTF-8

require 'spec_helper'

describe CloudModel::SshPubKey do
  it { expect(subject).to have_timestamps }
  it { expect(subject).to have_field(:key).of_type String }

  it { expect(subject).to validate_presence_of(:key) }
  it { expect(subject).to validate_uniqueness_of(:key) }

  it { expect(subject).to have_and_belong_to_many(:groups).as_inverse_of(:pub_keys).of_type CloudModel::SshGroup }

  describe 'to_s' do
    it 'should return the key' do
      subject.key = 'my_public_key'
      expect(subject.key).to eq 'my_public_key'
    end
  end

  describe '#from_file' do
    it 'should read file and create new key for each line' do
      allow(File).to receive(:readlines).with('~/my_ssh_keys').and_return [
        "  ssh key user@host1\n",
        "ssh key user@host2\n",
      ]

      expect(CloudModel::SshPubKey).to receive(:create!).with key: 'ssh key user@host1'
      expect(CloudModel::SshPubKey).to receive(:create!).with key: 'ssh key user@host2'

      CloudModel::SshPubKey.from_file '~/my_ssh_keys'
    end
  end

  describe 'name' do
    it 'should get the last part of ssh key as name' do
      subject.key = 'ssh-rsa my_public_key user@host.domain'
      expect(subject.name).to eq 'user@host.domain'
    end
  end

  describe 'authorized_keys sync' do
    let(:group) { CloudModel::SshGroup.create! name: "g-#{SecureRandom.hex(3)}" }

    before { allow(CloudModel::GuestJobs::SyncAuthorizedKeysJob).to receive(:perform_later) }

    it 'enqueues the sync for its groups when the key is created in a group' do
      expect(CloudModel::GuestJobs::SyncAuthorizedKeysJob).to receive(:perform_later).with([group.id.to_s])
      CloudModel::SshPubKey.create! key: "ssh-ed25519 AAAA#{SecureRandom.hex(4)} a@b", groups: [group]
    end

    it 'enqueues the sync for its former groups when the key is deleted' do
      key = CloudModel::SshPubKey.create! key: "ssh-ed25519 AAAA#{SecureRandom.hex(4)} a@b", groups: [group]
      expect(CloudModel::GuestJobs::SyncAuthorizedKeysJob).to receive(:perform_later).with([group.id.to_s])
      key.destroy
    end

    it 'does not enqueue for a key outside any group' do
      expect(CloudModel::GuestJobs::SyncAuthorizedKeysJob).not_to receive(:perform_later)
      CloudModel::SshPubKey.create! key: "ssh-ed25519 AAAA#{SecureRandom.hex(4)} a@b"
    end

    it 'does not fail the save when the job cannot be enqueued' do
      allow(CloudModel::GuestJobs::SyncAuthorizedKeysJob).to receive(:perform_later).and_raise 'queue down'
      allow(CloudModel).to receive(:log_exception)
      expect(CloudModel::SshPubKey.new(key: "ssh-ed25519 AAAA#{SecureRandom.hex(4)} a@b", groups: [group]).save).to eq true
    end
  end
end
