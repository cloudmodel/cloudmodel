# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Mixins::SmartToString do
  class TestSmartToStringModel
    include Mongoid::Document
    include CloudModel::Mixins::SmartToString
    
    field :name
  end
  
  subject { TestSmartToStringModel.new }
  
  context 'to_s' do
    it 'should return human readable model info' do
      subject.name = 'my model'
      expect(subject.to_s).to eq "Test smart to string model 'my model'"
    end
  end
end