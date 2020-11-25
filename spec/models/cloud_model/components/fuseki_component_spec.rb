# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::FusekiComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'name' do
    it 'should return :fuseki' do
      expect(subject.name).to eq :fuseki
    end
  end

  describe 'requirements' do
    it 'should require :java' do
      expect(subject.requirements).to eq [:java]
    end
  end
end