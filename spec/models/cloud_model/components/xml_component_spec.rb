# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::XmlComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'name' do
    it 'should return :xml' do
      expect(subject.name).to eq :xml
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end