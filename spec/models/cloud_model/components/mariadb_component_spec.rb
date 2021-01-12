# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::MariadbComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'name' do
    it 'should return :mariadb' do
      expect(subject.name).to eq :mariadb
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end