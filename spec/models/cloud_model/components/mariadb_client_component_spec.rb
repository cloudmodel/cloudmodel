# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::MariadbClientComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'name' do
    it 'should return :mariadb_client' do
      expect(subject.name).to eq :mariadb_client
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end