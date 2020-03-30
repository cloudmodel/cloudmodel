# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Ssh do
  it { expect(subject).to be_a CloudModel::Services::Base }
  
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 22 }
  it { expect(subject).to have_field(:authorized_keys).of_type Array }
  
  it { expect(subject.kind).to eq :ssh }
end