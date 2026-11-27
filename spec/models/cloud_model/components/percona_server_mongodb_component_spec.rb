# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::PerconaServerMongodbComponent do
  it 'should carry the line in its name' do
    subject.version = '8.0'
    expect(subject.name).to eq :"percona_server_mongodb@8.0"
    expect(subject.human_name).to eq 'Percona Server for MongoDB 8.0'
  end

  it 'should resolve from its symbol and find its worker' do
    component = CloudModel::Components::BaseComponent.from_sym :"percona_server_mongodb@8.0"
    expect(component).to be_a CloudModel::Components::PerconaServerMongodbComponent
    expect(component.worker(double(arch: 'amd64'), double)).to be_a CloudModel::Workers::Components::PerconaServerMongodbComponentWorker
  end
end
