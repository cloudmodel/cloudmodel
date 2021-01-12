# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::PhpMysqlComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'name' do
    it 'should return :php_mysql' do
      expect(subject.name).to eq :php_mysql
    end
  end

  describe 'requirements' do
    it 'should require mariadb_client and php' do
      expect(subject.requirements).to eq [:mariadb_client, :php]
    end
  end
end