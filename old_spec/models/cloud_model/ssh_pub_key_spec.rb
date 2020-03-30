# encoding: UTF-8

require 'spec_helper'

describe CloudModel::SshPubKey do
  it { expect(subject).to be_timestamped_document }  
  it { expect(subject).to have_field(:key).of_type String }

  it { expect(subject).to validate_presence_of(:key) }
  it { expect(subject).to validate_uniqueness_of(:key) }

  context 'to_s' do
    it 'should return the key' do
      subject.key = 'my_public_key'
      expect(subject.key).to eq 'my_public_key'
    end
  end
end