# encoding: UTF-8

require 'spec_helper'

describe CloudModel::SshGroup do
  it { expect(subject).to have_timestamps }
  it { expect(subject).to have_field(:name).of_type String }

  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name) }

  it { expect(subject).to have_field(:description).of_type String }

  it { expect(subject).to have_and_belong_to_many(:pub_keys).as_inverse_of(:groups).of_type CloudModel::SshPubKey }

  describe 'authorized_keys sync' do
    it 'enqueues the sync for the group when its keys change' do
      allow(CloudModel::GuestJobs::SyncAuthorizedKeysJob).to receive(:perform_later)
      group = CloudModel::SshGroup.create! name: "g-#{SecureRandom.hex(3)}"
      key = CloudModel::SshPubKey.create! key: "ssh-ed25519 AAAA#{SecureRandom.hex(4)} a@b"
      expect(CloudModel::GuestJobs::SyncAuthorizedKeysJob).to receive(:perform_later).with([group.id.to_s])
      group.update! pub_key_ids: [key.id]
    end

    it 'does not enqueue when only the description changes' do
      allow(CloudModel::GuestJobs::SyncAuthorizedKeysJob).to receive(:perform_later)
      group = CloudModel::SshGroup.create! name: "g-#{SecureRandom.hex(3)}"
      expect(CloudModel::GuestJobs::SyncAuthorizedKeysJob).not_to receive(:perform_later)
      group.update! description: 'deploy keys'
    end
  end
end
