# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::RubyComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }
  
  context 'name' do
    it 'should return :ruby' do
      expect(subject.name).to eq :ruby
    end
  end
  
  context 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end