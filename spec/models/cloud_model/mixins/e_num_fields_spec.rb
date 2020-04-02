# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Mixins::ENumFields do
  class TestENumFieldsModel
    include Mongoid::Document
    include CloudModel::Mixins::ENumFields
    
    enum_field :enum, values: {
      0x00 => :pending,
      0x10 => :testing,
      0x30 => :staging,
      0x40 => :production,
    }, default: :pending
  end
  
  subject { TestENumFieldsModel.new }
  
  it "should store enum value to enum_id field" do
    expect(subject).to have_field(:enum_id).of_type(Integer).with_default_value_of(0x00) 
  end
  
  it "should not have an enum field" do
    expect(subject).not_to have_field(:enum)
  end
  
  it "should allow to set enum by value" do
    subject.enum = :testing
    expect(subject.enum_id).to eq 0x10
  end
  
  it "should allow to set enum by id" do
    subject.enum_id = 0x30
    expect(subject.enum).to eq :staging
  end
  
  it "should return raw enum translation tables" do
    expect(TestENumFieldsModel.enum_fields).to eq({
      enum: {
        values: {
          0x00 => :pending,
          0x10 => :testing,
          0x30 => :staging,
          0x40 => :production
        }, 
        default: :pending
      }
    })
  end
end