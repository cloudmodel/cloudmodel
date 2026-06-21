# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Mongodb do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 27017 }
  it { expect(subject).to have_field(:mongodb_version).of_type(String).with_default_value_of "5.0" }
  it { expect(subject).to have_field(:mongodb_replication_priority).of_type(Integer).with_default_value_of 50 }
  it { expect(subject).to have_field(:mongodb_replication_arbiter_only).of_type(Mongoid::Boolean).with_default_value_of false }

  it { expect(subject).to belong_to(:mongodb_replication_set).of_type(CloudModel::MongodbReplicationSet).with_optional }

  it {expect(subject).to validate_inclusion_of(:mongodb_replication_priority).to_allow(0..100)}

  describe 'kind' do
    it 'should return :mongodb' do
      expect(subject.kind).to eq :mongodb
    end
  end

  describe 'allow_public_service?' do
    it 'should not allow public exposure' do
      expect(subject.allow_public_service?).to eq false
    end
  end

  describe 'components_needed' do
    it 'should require mongodb with default version' do
      expect(subject.components_needed).to eq [:'mongodb@5.0']
    end

    it 'should require mongodb with custom version' do
      subject.mongodb_version = '7.2'
      expect(subject.components_needed).to eq [:'mongodb@7.2']
    end
  end

  describe 'sanitize_service_data' do
    it 'should strip $ prefix from keys' do
      data = {'$db' => {'$count' => 5}, 'normal' => 'val'}
      result = subject.sanitize_service_data(data)
      expect(result).to eq({'db' => {'count' => 5}, 'normal' => 'val'})
    end
  end

  let(:guest) { double CloudModel::Guest, private_address: '10.42.0.1' }
  before { allow(subject).to receive(:guest).and_return(guest) }

  describe 'service_status' do
    it 'should return sanitized server status on success' do
      mongo_client = double 'mongo_client'
      database = double 'database'
      allow(Mongo::Client).to receive(:new).and_return(mongo_client)
      allow(mongo_client).to receive(:database).and_return(database)
      allow(database).to receive(:command).with('serverStatus' => true).and_return([{'connections' => {'current' => 5}}])
      allow(database).to receive(:command).with(getParameter: 1, featureCompatibilityVersion: 1).and_return([{'featureCompatibilityVersion' => {'version' => '5.0'}}])
      allow(mongo_client).to receive(:close)

      result = subject.service_status
      expect(result['connections']).to eq({'current' => 5})
      expect(result['featureCompatibilityVersion']).to eq '5.0'
    end

    it 'should return critical error on NoServerAvailable' do
      selector = double('selector', name: 'test', server_selection_timeout: 1, local_threshold: 0.015)
      allow(Mongo::Client).to receive(:new).and_raise(Mongo::Error::NoServerAvailable.new(selector))
      result = subject.service_status
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :critical
    end
  end

  describe 'mongodb_replication_priority' do
    it 'should return 0 if arbiter only' do
      subject.mongodb_replication_arbiter_only = true
      expect(subject.mongodb_replication_priority).to eq 0
    end

    it 'should return field value if not arbiter' do
      subject.mongodb_replication_arbiter_only = false
      subject.write_attribute(:mongodb_replication_priority, 75)
      expect(subject.mongodb_replication_priority).to eq 75
    end
  end

  describe 'mongodb_replication_set_master?' do
    it 'should return true when monitoring data shows this server as primary' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'repl' => {'primary' => '10.42.0.1:27017'}
      })
      expect(subject.mongodb_replication_set_master?).to eq true
    end

    it 'should return nil when no monitoring data' do
      allow(subject).to receive(:monitoring_last_check_result).and_return(nil)
      expect(subject.mongodb_replication_set_master?).to eq nil
    end
  end

  describe 'mongodb_replication_set_version' do
    it 'should return setVersion from monitoring data' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'repl' => {'setVersion' => 3}
      })
      expect(subject.mongodb_replication_set_version).to eq 3
    end

    it 'should return dash when no monitoring data' do
      allow(subject).to receive(:monitoring_last_check_result).and_return(nil)
      expect(subject.mongodb_replication_set_version).to eq '-'
    end
  end

  describe 'backupable?' do
    it 'should be true' do
      expect(subject.backupable?).to eq true
    end
  end

  describe 'backup' do
    before do
      allow(subject).to receive(:has_backups).and_return true
      allow(subject).to receive(:backup_directory).and_return('/backups/test')
      allow(FileUtils).to receive(:mkdir_p)
      allow(Rails.logger).to receive(:debug)
    end

    it 'should return false if has_backups is false' do
      allow(subject).to receive(:has_backups).and_return false
      expect(subject.backup).to eq false
    end

    it 'should run mongodump and return true on success' do
      allow(subject).to receive(:`) { `true`; '' }
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:rm_f)
      allow(FileUtils).to receive(:ln_s)
      allow(subject).to receive(:cleanup_backups)

      expect(subject.backup).to eq true
    end
  end

  describe 'restore' do
    it 'should run mongorestore and return true on success' do
      allow(subject).to receive(:backup_directory).and_return('/backups/test')
      allow(File).to receive(:exist?).with('/backups/test/latest').and_return(true)
      allow(Rails.logger).to receive(:debug)
      allow(subject).to receive(:`) { `true`; '' }

      expect(subject.restore).to eq true
    end

    it 'should return false if backup directory does not exist' do
      allow(subject).to receive(:backup_directory).and_return('/backups/test')
      allow(File).to receive(:exist?).with('/backups/test/latest').and_return(false)

      expect(subject.restore).to eq false
    end
  end
end