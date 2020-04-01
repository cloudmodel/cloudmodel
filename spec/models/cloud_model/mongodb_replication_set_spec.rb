# encoding: UTF-8

require 'spec_helper'

describe CloudModel::MongodbReplicationSet do
  it { expect(subject).to have_timestamps }  
    
  it { expect(subject).to have_field(:name).of_type(String) }
  
  context 'services' do
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
  
  context 'add_service' do
    it 'should add service to set' do
      service = double
      expect(service).to receive(:update_attribute).with(:mongodb_replication_set_id, subject.id)
      
      subject.add_service service
    end
  end
  
  context 'init_rs_cmd' do
    it 'should output mongodb command to init set' do
      subject.name = 'my_mongodb_set'
      
      service1 = double CloudModel::Services::Mongodb, port: 27017, private_address: '10.23.42.17'
      service2 = double CloudModel::Services::Mongodb, port: 1337, private_address: '10.23.42.240'
      allow(subject).to receive(:services).and_return [service1, service2]
      
      expect{ subject.init_rs_cmd }.to output(<<~OUT
        rs.initiate( {
           _id : "my_mongodb_set",
           members: [
              { _id: 0, host: "10.23.42.17:27017" },
              { _id: 1, host: "10.23.42.240:1337" },
           ]
        })
      OUT
      ).to_stdout
    end
  end
end