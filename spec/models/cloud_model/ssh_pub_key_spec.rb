# encoding: UTF-8

require 'spec_helper'

describe CloudModel::SshPubKey do
  it { expect(subject).to have_timestamps }  
  it { expect(subject).to have_field(:key).of_type String }

  it { expect(subject).to validate_presence_of(:key) }
  it { expect(subject).to validate_uniqueness_of(:key) }

  context 'to_s' do
    it 'should return the key' do
      subject.key = 'my_public_key'
      expect(subject.key).to eq 'my_public_key'
    end
  end
  
  context '#from_file' do
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
  
  context 'name' do
    it 'should get the last part of ssh key as name' do
      subject.key = 'ssh-rsa my_public_key user@host.domain'
      expect(subject.name).to eq 'user@host.domain'  
    end
  end
end