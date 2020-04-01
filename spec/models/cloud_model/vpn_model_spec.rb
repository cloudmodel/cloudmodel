# encoding: UTF-8

require 'spec_helper'

describe CloudModel::VpnClient do
  it { expect(subject).to have_timestamps }  
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:tinc_public_key).of_type String }
  it { expect(subject).to have_field(:address).of_type String }

  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name) }
  it { expect(subject).to validate_format_of(:name).to_allow("host-name-01") }
  it { expect(subject).to validate_format_of(:name).not_to_allow("Test Host") }
  it { expect(subject).to validate_presence_of(:tinc_public_key) }
  it { expect(subject).to validate_presence_of(:address) }
  it { expect(subject).to validate_format_of(:address).to_allow("127.0.0.1") }
  it { expect(subject).to validate_format_of(:address).not_to_allow("256.2.1.2") }
end