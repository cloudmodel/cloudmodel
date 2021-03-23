# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Mixins::ENumFields do
  class TestENumFieldsModel
    include Mongoid::Document
    include CloudModel::Mixins::ENumFields

    enum_field :enum, {
      0x00 => :pending,
      0x10 => :testing,
      0x30 => :staging,
      0x40 => :production,
    }, default: :pending
  end

  subject { TestENumFieldsModel.new }

  it 'should store enum value to enum_id field' do
    expect(subject).to have_field(:enum_id).of_type(Integer).with_default_value_of(0x00)
  end

  it 'should not have an enum field' do
    expect(subject).not_to have_field(:enum)
  end

  it 'should allow to set enum by value' do
    subject.enum = :testing
    expect(subject.enum_id).to eq 0x10
  end

  it 'should allow to set enum by id' do
    subject.enum_id = 0x30
    expect(subject.enum).to eq :staging
  end

  it 'should return raw enum translation tables' do
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

  describe 'enum_field' do
    it 'should allow to define new enum' do
      test_class = Class.new
      test_class.include Mongoid::Document
      test_class.include CloudModel::Mixins::ENumFields
      test_class.enum_field :test_field, {
        0x00 => :none
      }

      expect(test_class.new).to have_field(:test_field_id).of_type(Integer).with_default_value_of(nil)
    end

    it 'should allow to define new enum with default' do
      test_class = Class.new
      test_class.include Mongoid::Document
      test_class.include CloudModel::Mixins::ENumFields
      test_class.enum_field :test_field, {
        0x00 => :none,
        0x01 => :something
        }, default: :something

      expect(test_class.new).to have_field(:test_field_id).of_type(Integer).with_default_value_of(0x01)
    end

    it 'should silently drop default if value is invalid' do
      test_class = Class.new
      test_class.include Mongoid::Document
      test_class.include CloudModel::Mixins::ENumFields
      test_class.enum_field :test_field, {
        0x00 => :none,
        0x01 => :something
        }, default: :something_else

      expect(test_class.new).to have_field(:test_field_id).of_type(Integer).with_default_value_of(nil)
    end
  end

  describe 'seriablizable_hash' do
    it 'should resolve enum in serializable_hash' do
      subject.enum_id = 0x30

      expect(subject.serializable_hash['enum']).to eq :staging
      expect(subject.serializable_hash['enum_id']).to eq nil
    end

    # it 'should allow to call without enum mapper' do
    #   subject.enum_id = 0x30
    #
    #   expect(subject.serializable_hash_without_enum_enum['enum']).to eq nil
    #   expect(subject.serializable_hash_without_enum_enum['enum_id']).to eq 0x30
    # end
  end
end