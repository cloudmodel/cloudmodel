# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Tomcat do
  it { expect(subject).to be_a CloudModel::Services::Base }
  
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 8080 }
  it { expect(subject).to belong_to(:deploy_war_image).of_type(CloudModel::WarImage).as_inverse_of :services }
  
  it { expect(subject.kind).to eq :http }
end