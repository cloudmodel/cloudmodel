# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Redis do
  it { expect(subject).to be_a CloudModel::Services::Base }
  
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 6379 }
  
  it { expect(subject.kind).to eq :redis }
end