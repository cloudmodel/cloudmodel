# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::BaseComponent do
  describe 'name' do
    it 'should return :base' do
      expect(subject.name).to eq :base
    end
  end
  
  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end