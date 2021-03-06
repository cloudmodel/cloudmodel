# encoding: UTF-8

require 'spec_helper'

describe CloudModel::MongodbReplicationSet do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:name).of_type(String) }

  describe 'guests' do
    pending
  end

  describe 'services' do
    it 'should get array with all services using set' do
      guest1 = double CloudModel::Guest, services: []
      guest2 = double CloudModel::Guest, services: []
      guests = [guest1, guest2]
      guest1_mongodb_service = double CloudModel::Services::Mongodb
      guest1_services = [guest1_mongodb_service]
      guest2_mongodb_service = double CloudModel::Services::Mongodb
      guest2_services = [guest2_mongodb_service]

      expect(CloudModel::Guest).to receive(:where).with("services.mongodb_replication_set_id" => subject.id).and_return guests
      expect(guest1.services).to receive(:where).with(mongodb_replication_set_id: subject.id).and_return guest1_services
      expect(guest2.services).to receive(:where).with(mongodb_replication_set_id: subject.id).and_return guest2_services

      expect(subject.services).to eq [guest1_mongodb_service, guest2_mongodb_service]
    end
  end

  describe 'add_service' do
    it 'should add service to set' do
      service = double
      expect(service).to receive(:update_attribute).with(:mongodb_replication_set_id, subject.id)

      subject.add_service service
    end
  end

  describe 'init_rs_cmd' do
    it 'should return mongodb command to init set' do
      subject.name = 'my_mongodb_set'

      service1 = double(CloudModel::Services::Mongodb,
        port: 27017,
        private_address: '10.23.42.17',
        mongodb_replication_arbiter_only: false,
        mongodb_replication_priority: 50
      )
      service2 = double(CloudModel::Services::Mongodb,
        port: 1337,
        private_address: '10.23.42.240',
        mongodb_replication_arbiter_only: true,
        mongodb_replication_priority: 0
      )
      allow(subject).to receive(:services).and_return [service1, service2]

      expect(subject.init_rs_cmd).to eq(<<~OUT
        rs.initiate( {
           _id : "my_mongodb_set",
           members: [
              { _id: 0, host: "10.23.42.17:27017", arbiterOnly: false, priority: 50 },
              { _id: 1, host: "10.23.42.240:1337", arbiterOnly: true, priority: 0 },
           ]
        })
      OUT
      )
    end
  end

  describe 'service_uris' do
    pending
  end

  describe 'operational_service_uris' do
    pending
  end

  describe 'client' do
    pending
  end

  describe 'db_command' do
    pending
  end

  describe 'eval' do
    pending
  end

  describe 'initiate' do
    pending
  end

  describe 'status' do
    pending
  end

  describe 'read_config' do
    pending
  end

  describe 'reconfig' do
    pending
  end

  describe 'add' do
    pending
  end

  describe 'remove' do
    pending
  end
end