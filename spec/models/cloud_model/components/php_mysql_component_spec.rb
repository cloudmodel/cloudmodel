# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::PhpMysqlComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "php_mysql"' do
      expect(subject.base_name).to eq 'php_mysql'
    end

    it 'should return "php_mysql" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'php_mysql'
    end
  end

  describe 'name' do
    it 'should return :php_mysql' do
      expect(subject.name).to eq :php_mysql
    end

    it 'should return :php_mysql@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'php_mysql@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "PHP MySQL"' do
      expect(subject.human_name).to eq "PHP MySQL"
    end

    it 'should return "PHP MySQL 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "PHP MySQL 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::PhpMysqlComponentWorker

      expect(CloudModel::Workers::Components::PhpMysqlComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should require mariadb_client and php' do
      expect(subject.requirements).to eq [:mariadb_client, :php]
    end
  end
end