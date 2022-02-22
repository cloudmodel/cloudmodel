# encoding: UTF-8

require 'spec_helper'

describe CloudModel::SshGroup do
  it { expect(subject).to have_timestamps }
  it { expect(subject).to have_field(:name).of_type String }

  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name) }

  it { expect(subject).to have_field(:description).of_type String }

  it { expect(subject).to have_and_belong_to_many(:pub_keys).as_inverse_of(:groups).of_type CloudModel::SshPubKey }
end