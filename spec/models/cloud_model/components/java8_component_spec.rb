# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::Java8Component do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'name' do
    it 'should return :java8' do
      expect(subject.name).to eq :java8
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end