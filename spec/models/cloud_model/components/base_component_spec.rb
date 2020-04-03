# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::BaseComponent do
  context 'name' do
    it 'should return :base' do
      expect(subject.name).to eq :base
    end
  end
  
  context 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end