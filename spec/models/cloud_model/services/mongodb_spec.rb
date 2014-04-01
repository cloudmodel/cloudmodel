# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Mongodb do
  it { expect(subject).to be_a CloudModel::Services::Base }
  
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 27017 }
  
  it { expect(subject.kind).to eq :mongodb }
end