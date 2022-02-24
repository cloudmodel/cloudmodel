# encoding: UTF-8

require 'spec_helper'

describe CloudModel::RedisSentinelSet do
  it { expect(subject).to have_timestamps }
  it { expect(subject).to belong_to(:master_service).of_type(CloudModel::Services::Redis).with_optional }

  it { expect(subject).to have_field(:name).of_type(String) }

  describe 'services' do
    it 'should get array with all services using set' do
      guest1 = double CloudModel::Guest, services: []
      guest2 = double CloudModel::Guest, services: []
      guests = [guest1, guest2]
      guest1_mongodb_service = double CloudModel::Services::Redis
      guest1_services = [guest1_mongodb_service]
      guest2_mongodb_service = double CloudModel::Services::Redis
      guest2_services = [guest2_mongodb_service]

      expect(CloudModel::Guest).to receive(:where).with("services.redis_sentinel_set_id" => subject.id).and_return guests
      expect(guest1.services).to receive(:where).with(redis_sentinel_set_id: subject.id).and_return guest1_services
      expect(guest2.services).to receive(:where).with(redis_sentinel_set_id: subject.id).and_return guest2_services

      expect(subject.services).to eq [guest1_mongodb_service, guest2_mongodb_service]
    end
  end

  describe 'add_service' do
    it 'should add service to set' do
      service = double
      expect(service).to receive(:update_attribute).with(:redis_sentinel_set_id, subject.id)

      subject.add_service service
    end
  end

  describe 'master_service' do
    it 'should return master service if master_service is set' do
      service = double CloudModel::Services::Redis, id: BSON::ObjectId.new
      subject.master_service_id = service.id
      expect(CloudModel::Services::Base).to receive(:find).with(service.id).and_return service

      expect(subject.master_service).to eq service
    end

    it 'should first service if no master_service is set' do
      service = double CloudModel::Services::Redis, id: BSON::ObjectId.new
      expect(subject).to receive(:services).and_return [service, double]

      expect(subject.master_service).to eq service
    end
  end

  describe 'master_node' do
    it 'should return guest of master_service' do
      guest = double CloudModel::Guest
      allow(subject).to receive(:master_service).and_return double(CloudModel::Services::Redis, guest: guest)

      expect(subject.master_node).to eq guest
    end
  end

  describe 'master_address' do
    it 'should return address of master_node' do
      guest = double CloudModel::Guest, private_address: '10.42.23.17'
      allow(subject).to receive(:master_node).and_return guest

      expect(subject.master_address).to eq '10.42.23.17'
    end
  end

  describe 'sentinel_hosts' do
    it 'should return array of ip and port mapping of services' do
      allow(subject).to receive(:services).and_return [
        double(CloudModel::Services::Redis, private_address: '10.42.23.17', redis_sentinel_port: 26379),
        double(CloudModel::Services::Redis, private_address: '10.42.23.117', redis_sentinel_port: 1337)
      ]

      expect(subject.sentinel_hosts).to eq [{"ip"=>"10.42.23.17", "port"=>26379}, {"ip"=>"10.42.23.117", "port"=>1337}]
    end
  end

  describe 'status' do
    pending
  end
end