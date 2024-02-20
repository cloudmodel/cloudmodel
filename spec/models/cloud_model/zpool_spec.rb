# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Zpool do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to be_embedded_in(:host).of_type CloudModel::Host }

  it { expect(subject).to have_field(:name).of_type String }

  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name) }

  it { expect(subject).to have_field(:init_string).of_type String }

  describe '#to_hash' do
    it 'should transform zpools to hash' do
      zpools = [Factory.build(:zpool), Factory.build(:zpool)]
      allow(CloudModel::Zpool).to receive(:scoped).and_return zpools

      expect(CloudModel::Zpool.as_hash).to eq({
        zpools[0].name.to_sym => zpools[0].init_string,
        zpools[1].name.to_sym => zpools[1].init_string
      })
    end
  end
end