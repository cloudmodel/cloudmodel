# encoding: UTF-8

require 'spec_helper'

describe CloudModel::MongodbReplicationSet do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:name).of_type(String) }
  it { expect(subject).to have_field(:active).of_type(Mongoid::Boolean) }

  describe 'CloudModel.mongodb_version_path' do
    it 'should return known versions of mongodb' do
      expect(CloudModel.mongodb_version_path).to eq ["3.2", "3.4", "3.6", "4.0", "4.2", "4.4", "5.0", "6.0", "7.0", "8.0", "8.2"]
    end
  end

  describe 'guests' do
    it 'should query guests with matching service set id' do
      expect(CloudModel::Guest).to receive(:where).with("services.mongodb_replication_set_id" => subject.id)
      subject.guests
    end
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

  describe 'feature_compatibility_version' do
    it 'should get the feature_compatibility_version from db' do
      expect(subject).to receive(:db_command).with(getParameter: 1, featureCompatibilityVersion: 1).and_return [{'featureCompatibilityVersion' => {'version' => '4.2'}}]

      expect(subject.feature_compatibility_version).to eq '4.2'
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
    it 'should return array of server URIs' do
      s1 = double 'service1', server_uri: '10.42.0.1:27017'
      s2 = double 'service2', server_uri: '10.42.0.2:27017'
      allow(subject).to receive(:services).and_return([s1, s2])

      expect(subject.service_uris).to eq ['10.42.0.1:27017', '10.42.0.2:27017']
    end
  end

  describe 'operational_service_uris' do
    it 'should exclude services in critical state' do
      s1 = double 'service1', server_uri: '10.42.0.1:27017', state: :ok
      s2 = double 'service2', server_uri: '10.42.0.2:27017', state: :critical
      allow(subject).to receive(:services).and_return([s1, s2])

      expect(subject.operational_service_uris).to eq ['10.42.0.1:27017']
    end
  end

  describe 'client' do
    it 'should return Mongo::Client when initiated and services available' do
      allow(subject).to receive(:initiated?).and_return(true)
      allow(subject).to receive(:operational_service_uris).and_return(['10.42.0.1:27017'])
      mongo_client = double 'mongo_client'
      allow(Mongo::Client).to receive(:new).and_return(mongo_client)

      expect(subject.client).to eq mongo_client
    end

    it 'should return nil when not initiated' do
      allow(subject).to receive(:initiated?).and_return(false)
      expect(subject.client).to eq nil
    end
  end

  describe 'db_command' do
    it 'should execute command via client' do
      mongo_client = double 'mongo_client'
      database = double 'database'
      allow(subject).to receive(:client).and_return(mongo_client)
      allow(mongo_client).to receive(:database).and_return(database)
      allow(database).to receive(:command).and_return(double(documents: [{'ok' => 1}]))
      allow(mongo_client).to receive(:close)

      expect(subject.db_command(replSetGetStatus: true)).to eq [{'ok' => 1}]
    end

    it 'should return nil when no client' do
      allow(subject).to receive(:client).and_return(nil)
      expect(subject.db_command(replSetGetStatus: true)).to eq nil
    end
  end

  describe 'eval' do
    # eval is commented out in source
  end

  describe 'initiate' do
    it 'should return false when no guests' do
      allow(subject).to receive(:guests).and_return([])

      success, msg = subject.initiate
      expect(success).to eq false
    end

    it 'should run mongosh on first guest' do
      guest = double 'guest'
      allow(subject).to receive(:guests).and_return([guest])
      allow(subject).to receive(:init_rs_cmd).and_return('rs.initiate({})')
      allow(guest).to receive(:exec).and_return([true, '"ok" : 1'])
      allow(subject).to receive(:update_attribute)
      allow(CloudModel::Monitoring::MongodbReplicationSetChecks).to receive_message_chain(:new, :check)

      success, _msg = subject.initiate
      expect(success).to eq true
    end
  end

  describe 'status' do
    it 'should merge service info with db status' do
      service = double 'service', server_uri: '10.42.0.1:27017'
      allow(subject).to receive(:services).and_return([service])
      allow(subject).to receive(:db_command).and_return([{
        'members' => [{'name' => '10.42.0.1:27017', 'stateStr' => 'PRIMARY'}],
        '$clusterTime' => '2024-01-01'
      }])

      result = subject.status
      expect(result['members'].first['found']).to eq true
      expect(result['clusterTime']).to eq '2024-01-01'
    end
  end

  describe 'read_config' do
    it 'should return config from db_command' do
      allow(subject).to receive(:db_command).and_return([{
        'config' => {'_id' => 'test', 'version' => 1, 'members' => []},
        'commitmentStatus' => true
      }])

      expect(subject.read_config['_id']).to eq 'test'
    end

    it 'should raise on exception in response' do
      allow(subject).to receive(:db_command).and_return([{
        'retval' => {error: 'fail'}, 'exception' => 'Error'
      }])

      expect { subject.read_config }.to raise_error(RuntimeError)
    end
  end

  describe 'reconfig' do
    it 'should update config with current services' do
      service = double 'service', server_uri: '10.42.0.1:27017',
                        mongodb_replication_priority: 50,
                        mongodb_replication_arbiter_only: false
      allow(subject).to receive(:services).and_return([service])
      allow(subject).to receive(:read_config).and_return({
        'version' => 1,
        'members' => [{'_id' => 0, 'host' => '10.42.0.1:27017', 'arbiterOnly' => false}]
      })
      allow(subject).to receive(:db_command).and_return([{'ok' => 1}])

      result = subject.reconfig
      expect(result.first['ok']).to eq 1
    end
  end

  # describe 'add' do
  #   pending
  # end
  #
  # describe 'remove' do
  #   pending
  # end

  describe 'update_feature_compatibility_version!' do
    it 'should return false for unknown version' do
      expect { subject.update_feature_compatibility_version!('99.0') }.to output(/not in the allowed/).to_stdout
    end

    it 'should return false when no services' do
      allow(subject).to receive(:services).and_return([])
      expect { subject.update_feature_compatibility_version!('5.0') }.to output(/No services/).to_stdout
    end
  end
end