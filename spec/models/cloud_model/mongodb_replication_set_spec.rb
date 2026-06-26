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

    it 'should return nil when db_command raises' do
      allow(subject).to receive(:db_command).and_raise(RuntimeError.new('boom'))

      expect(subject.feature_compatibility_version).to eq nil
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

    it 'should return nil when no operational services' do
      allow(subject).to receive(:initiated?).and_return(true)
      allow(subject).to receive(:operational_service_uris).and_return([])

      expect(subject.client).to eq nil
    end

    it 'should return false when Mongo::Client raises' do
      allow(subject).to receive(:initiated?).and_return(true)
      allow(subject).to receive(:operational_service_uris).and_return(['10.42.0.1:27017'])
      allow(Mongo::Client).to receive(:new).and_raise(StandardError.new('no connect'))

      expect(subject.client).to eq false
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

    it 'should close client even on success' do
      mongo_client = double 'mongo_client'
      database = double 'database'
      allow(subject).to receive(:client).and_return(mongo_client)
      allow(mongo_client).to receive(:database).and_return(database)
      allow(database).to receive(:command).and_return(double(documents: [{'ok' => 1}]))
      expect(mongo_client).to receive(:close)

      subject.db_command(replSetGetStatus: true)
    end

    it 'should return error document and close client when command raises' do
      mongo_client = double 'mongo_client'
      database = double 'database'
      allow(subject).to receive(:client).and_return(mongo_client)
      allow(mongo_client).to receive(:database).and_return(database)
      allow(database).to receive(:command).and_raise(StandardError.new('cmd failed'))
      expect(mongo_client).to receive(:close)

      result = subject.db_command(replSetGetStatus: true)
      expect(result.first['retval'][:error]).to match(/Can.t execute/)
      expect(result.first['exception']).to match(/cmd failed/)
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

    it 'should set initiated to true and run monitoring check on success' do
      guest = double 'guest'
      allow(subject).to receive(:guests).and_return([guest])
      allow(subject).to receive(:init_rs_cmd).and_return('rs.initiate({})')
      allow(guest).to receive(:exec).and_return([true, '"ok" : 1'])
      check = double 'check'
      expect(subject).to receive(:update_attribute).with(:initiated, true)
      expect(CloudModel::Monitoring::MongodbReplicationSetChecks).to receive(:new).with(subject).and_return(check)
      expect(check).to receive(:check)

      success, _msg = subject.initiate
      expect(success).to eq true
    end

    it 'should treat "ok : 0" output as failure and not set initiated' do
      guest = double 'guest'
      allow(subject).to receive(:guests).and_return([guest])
      allow(subject).to receive(:init_rs_cmd).and_return('rs.initiate({})')
      allow(guest).to receive(:exec).and_return([true, '{ "ok" : 0 }'])
      allow(CloudModel::Monitoring::MongodbReplicationSetChecks).to receive_message_chain(:new, :check)
      expect(subject).not_to receive(:update_attribute)

      success, _msg = subject.initiate
      expect(success).to eq false
    end

    it 'should return exec result unchanged when exec fails' do
      guest = double 'guest'
      allow(subject).to receive(:guests).and_return([guest])
      allow(subject).to receive(:init_rs_cmd).and_return('rs.initiate({})')
      allow(guest).to receive(:exec).and_return([false, 'ssh error'])
      expect(subject).not_to receive(:update_attribute)

      success, msg = subject.initiate
      expect(success).to eq false
      expect(msg).to eq 'ssh error'
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

    it 'should add a not-found N/C member when service is not in db members' do
      service = double 'service', server_uri: '10.42.0.9:27017'
      allow(subject).to receive(:services).and_return([service])
      allow(subject).to receive(:db_command).and_return([{
        'members' => [{'name' => '10.42.0.1:27017', 'stateStr' => 'PRIMARY'}],
        '$clusterTime' => '2024-01-01'
      }])

      result = subject.status
      added = result['members'].find { |m| m['name'] == '10.42.0.9:27017' }
      expect(added['found']).to eq false
      expect(added['state']).to eq(-1)
      expect(added['stateStr']).to eq 'N/C'
      expect(added['service']).to eq service
    end

    it 'should default to empty data when db_command returns nil' do
      allow(subject).to receive(:services).and_return([])
      allow(subject).to receive(:db_command).and_return(nil)

      result = subject.status
      expect(result['members']).to eq []
      expect(result['clusterTime']).to eq nil
    end

    it 'should replace service objects with ids when service_id_only set' do
      host = double 'host'
      allow(host).to receive(:id).and_return('host-id')
      guest = double 'guest', host_id: 'host-id', id: 'guest-id'
      service = double 'service', server_uri: '10.42.0.1:27017', guest: guest, id: 'service-id'
      allow(subject).to receive(:services).and_return([service])
      allow(subject).to receive(:db_command).and_return([{
        'members' => [{'name' => '10.42.0.1:27017', 'stateStr' => 'PRIMARY'}],
        '$clusterTime' => '2024-01-01'
      }])

      result = subject.status(service_id_only: true)
      member = result['members'].first
      expect(member['host_id']).to eq 'host-id'
      expect(member['guest_id']).to eq 'guest-id'
      expect(member['service_id']).to eq 'service-id'
      expect(member).not_to have_key('service')
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

      expect { subject.read_config }.to raise_error(RuntimeError, /fail/)
    end

    it 'should raise when commitmentStatus is not committed' do
      allow(subject).to receive(:db_command).and_return([{
        'config' => {'_id' => 'test', 'version' => 1, 'members' => []},
        'commitmentStatus' => false
      }])

      expect { subject.read_config }.to raise_error(RuntimeError, /not been committed/)
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

    it 'should add a new member for services not yet in config and bump version' do
      service = double 'service', server_uri: '10.42.0.2:27017',
                        mongodb_replication_priority: 30,
                        mongodb_replication_arbiter_only: false,
                        guest: double('guest')
      allow(service).to receive(:to_s).and_return('mongo-svc')
      allow(subject).to receive(:services).and_return([service])
      allow(subject).to receive(:read_config).and_return({
        'version' => 5,
        'members' => [{'_id' => 0, 'host' => '10.42.0.1:27017', 'arbiterOnly' => false}]
      })

      expect(subject).to receive(:db_command) do |arg|
        config = arg[:replSetReconfig]
        expect(config['version']).to eq 6
        new_member = config['members'].find { |m| m['host'] == '10.42.0.2:27017' }
        expect(new_member['_id']).to eq 1
        expect(new_member['priority']).to eq 30
        [{'ok' => 1}]
      end

      subject.reconfig
    end

    it 'should initiate then re-read config when read_config first fails' do
      service = double 'service', server_uri: '10.42.0.1:27017',
                        mongodb_replication_priority: 50,
                        mongodb_replication_arbiter_only: false
      allow(subject).to receive(:services).and_return([service])
      call = 0
      allow(subject).to receive(:read_config) do
        call += 1
        raise(RuntimeError, 'no config') if call == 1
        {'version' => 1, 'members' => [{'_id' => 0, 'host' => '10.42.0.1:27017', 'arbiterOnly' => false}]}
      end
      expect(subject).to receive(:initiate)
      allow(subject).to receive(:db_command).and_return([{'ok' => 1}])

      expect { subject.reconfig }.to output(/no config/).to_stdout
    end

    it 'should reconfig recursively when arbiter setting changed' do
      service = double 'service', server_uri: '10.42.0.1:27017',
                        mongodb_replication_priority: 50,
                        mongodb_replication_arbiter_only: true,
                        guest: double('guest')
      allow(service).to receive(:to_s).and_return('mongo-svc')
      allow(subject).to receive(:services).and_return([service])

      # First read_config has the old arbiter setting (false) which differs from the
      # service (true), so reconfig drops the member and recurses. On the recursion the
      # config already reflects arbiterOnly true, so no further change and it terminates.
      config_call = 0
      allow(subject).to receive(:read_config) do
        config_call += 1
        if config_call == 1
          {'version' => 1, 'members' => [{'_id' => 0, 'host' => '10.42.0.1:27017', 'arbiterOnly' => false}]}
        else
          {'version' => 2, 'members' => [{'_id' => 1, 'host' => '10.42.0.1:27017', 'arbiterOnly' => true}]}
        end
      end
      allow(subject).to receive(:db_command).and_return([{'ok' => 1}])

      result = nil
      expect { result = subject.reconfig }.to output(/Reconfig again/).to_stdout
      expect(subject).to have_received(:read_config).twice
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

    it 'should return false when already on requested feature level' do
      allow(subject).to receive(:services).and_return([double('service')])
      allow(subject).to receive(:feature_compatibility_version).and_return('5.0')

      result = nil
      expect { result = subject.update_feature_compatibility_version!('5.0') }.to output(/Already on requested/).to_stdout
      expect(result).to eq false
    end

    it 'should refuse to downgrade' do
      allow(subject).to receive(:services).and_return([double('service')])
      allow(subject).to receive(:feature_compatibility_version).and_return('6.0')

      result = nil
      expect { result = subject.update_feature_compatibility_version!('5.0') }.to output(/can not downgrade/).to_stdout
      expect(result).to eq false
    end

    it 'should upgrade one step, redeploy outdated services and set new FCV' do
      guest = double 'guest', name: 'g1'
      allow(guest).to receive(:host).and_return(double('host', name: 'h1'))
      service = double 'service', name: 'mongo',
                        guest: guest,
                        service_status: {'version' => '5.0'},
                        mongodb_version: '6.0'
      allow(service).to receive(:update_attribute)
      allow(guest).to receive(:redeploy!)
      allow(subject).to receive(:services).and_return([service])
      allow(subject).to receive(:feature_compatibility_version).and_return('5.0')
      allow(subject).to receive(:sleep)
      allow(subject).to receive(:db_command).and_return([{'ok' => 1}])

      result = nil
      expect {
        result = subject.update_feature_compatibility_version!('6.0')
      }.to output(/Set Feature Compatibility Version to 6.0/).to_stdout

      expect(service).to have_received(:update_attribute).with(:mongodb_version, '6.0')
      expect(guest).to have_received(:redeploy!).with(force: true, debug: nil)
      expect(subject).to have_received(:db_command).with(setFeatureCompatibilityVersion: '6.0')
      expect(result).to eq true
    end

    it 'should not redeploy when service version already matches target step' do
      guest = double 'guest', name: 'g1'
      allow(guest).to receive(:host).and_return(double('host', name: 'h1'))
      service = double 'service', name: 'mongo',
                        guest: guest,
                        service_status: {'version' => '6.0'},
                        mongodb_version: '6.0'
      allow(service).to receive(:update_attribute)
      allow(subject).to receive(:services).and_return([service])
      allow(subject).to receive(:feature_compatibility_version).and_return('5.0')
      allow(subject).to receive(:db_command).and_return([{'ok' => 1}])

      expect(guest).not_to receive(:redeploy!)
      expect(subject).not_to receive(:sleep)

      result = nil
      expect {
        result = subject.update_feature_compatibility_version!('6.0')
      }.to output(/Set Feature Compatibility Version to 6.0/).to_stdout
      expect(result).to eq true
    end
  end

  it { expect(subject).to have_field(:has_backups).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:backups_enabled_at).of_type(Time) }
  it { expect(subject).to have_field(:mongodb_backup_exclude_collection_prefixes).of_type(Array).with_default_value_of [] }
  it { expect(subject).to belong_to(:web_image).of_type(CloudModel::WebImage).with_optional }

  describe 'mongodb_backup_exclude_collection_prefixes=' do
    it 'splits a whitespace/comma separated string into an array' do
      subject.mongodb_backup_exclude_collection_prefixes = 'fs, audit'
      expect(subject.mongodb_backup_exclude_collection_prefixes).to eq %w(fs audit)
    end
  end

  describe 'backup_directory' do
    it 'should be namespaced per replica set' do
      allow(CloudModel.config).to receive(:backup_directory).and_return '/var/backups'
      expect(subject.backup_directory).to eq "/var/backups/mongodb_replication_sets/#{subject.id}"
    end
  end

  describe 'backup_member' do
    it 'should pick a non-arbiter secondary' do
      primary   = double 'primary',   mongodb_replication_arbiter_only: false, mongodb_replication_set_master?: true
      secondary = double 'secondary', mongodb_replication_arbiter_only: false, mongodb_replication_set_master?: false
      arbiter   = double 'arbiter',   mongodb_replication_arbiter_only: true,  mongodb_replication_set_master?: false
      allow(subject).to receive(:services).and_return([primary, arbiter, secondary])

      expect(subject.backup_member).to eq secondary
    end
  end

  describe 'backup_exclude_collection_prefixes' do
    it 'uses the web image prefixes when a web image is set' do
      subject.mongodb_backup_exclude_collection_prefixes = %w(own)
      subject.web_image = CloudModel::WebImage.new(mongodb_backup_exclude_collection_prefixes: %w(fs tantivy_journal))
      expect(subject.backup_exclude_collection_prefixes).to eq %w(fs tantivy_journal)
    end

    it 'uses its own prefixes when no web image is set' do
      subject.mongodb_backup_exclude_collection_prefixes = %w(own audit)
      expect(subject.backup_exclude_collection_prefixes).to eq %w(own audit)
    end

    it 'is empty without own prefixes or a web image' do
      expect(subject.backup_exclude_collection_prefixes).to eq []
    end
  end

  describe 'backup' do
    let(:guest) { double 'guest', private_address: '10.0.0.5' }
    let(:member) { double 'member', guest: guest, port: 27017, mongodb_replication_arbiter_only: false, mongodb_replication_set_master?: false }

    before do
      subject.has_backups = true
      allow(subject).to receive(:backup_directory).and_return('/backups/rs')
      allow(subject).to receive(:services).and_return([member])
      allow(FileUtils).to receive(:mkdir_p)
      allow(FileUtils).to receive(:rm_f)
      allow(FileUtils).to receive(:rm_rf)
      allow(FileUtils).to receive(:ln_s)
      allow(subject).to receive(:cleanup_backups)
      allow(Rails.logger).to receive(:debug)
      allow(Rails.logger).to receive(:error)
      allow(subject).to receive(:`) { `true`; '' }
    end

    it 'should return false unless has_backups' do
      subject.has_backups = false
      expect(subject.backup).to eq false
    end

    it 'should run a single full mongodump against the secondary and symlink latest' do
      allow(subject).to receive(:backup_exclude_collection_prefixes).and_return([])
      expect(subject).to receive(:`).with(/mongodump --gzip --readPreference=secondary -h 10.0.0.5 --port 27017 -o \/backups\/rs\/[0-9]{14}/) { `true`; '' }
      expect(FileUtils).to receive(:ln_s)

      expect(subject.backup).to eq true
    end

    it 'should dump each database with exclusion flags when configured' do
      allow(subject).to receive(:backup_exclude_collection_prefixes).and_return(%w(fs tantivy_journal))
      allow(subject).to receive(:backup_databases).and_return(%w(core_graph_production))
      expect(subject).to receive(:`).with(/--db core_graph_production .*--excludeCollectionsWithPrefix=fs --excludeCollectionsWithPrefix=tantivy_journal/) { `true`; '' }

      expect(subject.backup).to eq true
    end
  end

  describe 'restore' do
    it 'refuses to restore without force' do
      expect { subject.restore }.to raise_error(CloudModel::BackupError, /force: true/)
    end
  end

  describe '.backup_all' do
    it 'should back up each set with backups and notify on failure' do
      good = double 'good', name: 'good'
      bad  = double 'bad',  name: 'bad', id: 'id1'
      expect(good).to receive(:backup)
      allow(bad).to receive(:backup).and_raise('boom')
      rel = double 'rel', to_a: [good, bad]
      allow(CloudModel::MongodbReplicationSet).to receive(:where).with(has_backups: true).and_return(rel)

      expect { CloudModel::MongodbReplicationSet.backup_all }.to output(/Backup of replication set bad failed/).to_stdout
    end
  end
end