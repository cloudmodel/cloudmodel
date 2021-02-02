# encoding: UTF-8

require 'spec_helper'

describe CloudModel::MariadbGaleraCluster do
  it { expect(subject).to have_timestamps }

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

      expect(CloudModel::Guest).to receive(:where).with("services.mariadb_galera_cluster_id" => subject.id).and_return guests
      expect(guest1.services).to receive(:where).with(mariadb_galera_cluster_id: subject.id).and_return guest1_services
      expect(guest2.services).to receive(:where).with(mariadb_galera_cluster_id: subject.id).and_return guest2_services

      expect(subject.services).to eq [guest1_mongodb_service, guest2_mongodb_service]
    end
  end

  describe 'add_service' do
    it 'should add service to set' do
      service = double
      expect(service).to receive(:update_attribute).with(:mariadb_galera_cluster_id, subject.id)

      subject.add_service service
    end
  end

  describe 'cluster_hosts' do
    it 'should return array of ip and port mapping of services' do
      allow(subject).to receive(:services).and_return [
        double(CloudModel::Services::Mariadb, private_address: '10.42.23.17', mariadb_galera_port: 26379),
        double(CloudModel::Services::Mariadb, private_address: '10.42.23.117', mariadb_galera_port: 1337)
      ]

      expect(subject.cluster_hosts).to eq [{"ip"=>"10.42.23.17", "port"=>26379}, {"ip"=>"10.42.23.117", "port"=>1337}]
    end
  end

  describe 'cluster_hosts_string' do
    it 'should return array of ip and port mapping of services' do
      allow(subject).to receive(:cluster_hosts).and_return [{"ip"=>"10.42.23.17", "port"=>26379}, {"ip"=>"10.42.23.117", "port"=>1337}]

      expect(subject.cluster_hosts_string).to eq "10.42.23.17:26379,10.42.23.117:1337"
    end
  end


end