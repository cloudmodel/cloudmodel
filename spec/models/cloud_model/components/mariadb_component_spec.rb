# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::MariadbComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "mariadb"' do
      expect(subject.base_name).to eq 'mariadb'
    end

    it 'should return "mariadb" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'mariadb'
    end
  end

  describe 'name' do
    it 'should return :mariadb' do
      expect(subject.name).to eq :mariadb
    end

    it 'should return :mariadb@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'mariadb@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "MariaDB"' do
      expect(subject.human_name).to eq "MariaDB"
    end

    it 'should return "MariaDB 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "MariaDB 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      worker_class = double CloudModel::Workers::Components::MariadbComponentWorker

      expect(CloudModel::Workers::Components::MariadbComponentWorker).to receive(:new).with(host, component: subject).and_return worker_class
      expect(subject.worker host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should require mariadb_client' do
      expect(subject.requirements).to eq [:mariadb_client]
    end
  end
end