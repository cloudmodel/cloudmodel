# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Mariadb do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject.allow_public_service?).to eq false }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 3306 }
  it { expect(subject).to have_field(:mariadb_galera_port).of_type(Integer).with_default_value_of 4567 }

  it { expect(subject).to belong_to(:mariadb_galera_cluster).of_type(CloudModel::MariadbGaleraCluster).with_optional }

  describe 'kind' do
    it 'should return :mariadb' do
      expect(subject.kind).to eq :mariadb
    end
  end

  describe 'components_needed' do
    it 'should require only mariadb' do
      expect(subject.components_needed).to eq [:mariadb]
    end
  end

  describe 'service_status' do
    let(:client) {double close:true, query:[]}

    before do
      allow(subject).to receive(:guest).and_return double private_address: '10.42.23.1'
      allow(Mysql2::Client).to receive(:new).with(host: '10.42.23.1', username: 'monitoring').and_return client
    end

    it 'should get mysql status' do
      expect(Mysql2::Client).to receive(:new).with(host: '10.42.23.1', username: 'monitoring').and_return client
      expect(client).to receive(:query).with("SHOW STATUS")

      subject.service_status
    end

    it 'should transform mysql result as hash' do
      expect(client).to receive(:query).with("SHOW STATUS").and_return [
        {'Variable_name' => 'some_item', 'Value' => 'some value'},
        {'Variable_name' => 'some_other_item', 'Value' => 'some other value'},
      ]
      expect(subject.service_status).to eq(
        'some_item' => 'some value',
        'some_other_item' => 'some other value',
      )
    end

    it 'should close the mysql client connection' do
      expect(client).to receive(:close)
      subject.service_status
    end

    it 'should return error with exception' do
      allow(Mysql2::Client).to receive(:new).and_raise 'DB not connectable'
      expect(subject.service_status).to eq(
        error: "Failed to get db status\nRuntimeError\n\nDB not connectable",
        key: :not_reachable,
        severity: :critical
      )
    end
  end

  describe 'backupable?' do
    it 'should be true' do
      expect(subject.backupable?).to eq true
    end
  end

  describe 'backup' do
    before do
      allow(subject).to receive(:guest).and_return double(private_address: '10.42.23.1')
      allow(subject).to receive(:has_backups).and_return true
      allow(subject).to receive(:backup_directory).and_return('/backups/test')
      allow(FileUtils).to receive(:mkdir_p)
      allow(Rails.logger).to receive(:debug)
    end

    it 'should return false if has_backups is false' do
      allow(subject).to receive(:has_backups).and_return false
      expect(subject.backup).to eq false
    end

    it 'should run mysqldump and return true on success' do
      allow(subject).to receive(:`) { `true`; '' }
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:rm_f)
      allow(FileUtils).to receive(:ln_s)
      allow(subject).to receive(:cleanup_backups)

      expect(subject.backup).to eq true
    end

    it 'should create the missing backup user and retry once on access denied' do
      calls = 0
      allow(subject).to receive(:`) do
        calls += 1
        if calls == 1
          `false`; "mysqldump: Got error: 1045: \"Access denied for user 'backup'@'10.42.23.9' (using password: NO)\""
        else
          `true`; ''
        end
      end
      expect(subject).to receive(:ensure_backup_user).and_return(true)
      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:rm_f)
      allow(FileUtils).to receive(:ln_s)
      allow(subject).to receive(:cleanup_backups)

      expect(subject.backup).to eq true
      expect(calls).to eq 2
    end

    it 'should not retry when the backup user cannot be created' do
      calls = 0
      allow(subject).to receive(:`) { calls += 1; `false`; 'Access denied' }
      expect(subject).to receive(:ensure_backup_user).and_return(false)
      allow(FileUtils).to receive(:rm_rf)

      expect(subject.backup).to eq false
      expect(calls).to eq 1
    end

    it 'should not touch the backup user on other failures' do
      allow(subject).to receive(:`) { `false`; 'mysqldump: Got error: 2002: connection refused' }
      expect(subject).not_to receive(:ensure_backup_user)
      allow(FileUtils).to receive(:rm_rf)

      expect(subject.backup).to eq false
    end
  end

  describe 'ensure_backup_user' do
    let(:guest) { double 'guest', name: 'db-guest', private_address: '10.42.23.1' }

    before do
      allow(subject).to receive(:guest).and_return guest
    end

    it 'should create the passwordless dump user limited to the VPN /16 via the guest socket' do
      expect(guest).to receive(:exec) do |command|
        expect(command).to match(/\Amysql -e /)
        plain = command.gsub('\\', '') # undo shellescaping for readability
        expect(plain).to include 'CREATE USER IF NOT EXISTS'
        expect(plain).to include "'backup'@'10.42.%'"
        expect(plain).to include 'SELECT, SHOW VIEW, TRIGGER, LOCK TABLES, PROCESS, EVENT'
        [true, '']
      end

      expect(subject.ensure_backup_user).to eq true
    end

    it 'should log and return false when the user cannot be created' do
      allow(guest).to receive(:exec).and_return([false, 'ERROR 2002: no socket'])
      expect(Rails.logger).to receive(:error).with(/backup user on db-guest/)

      expect(subject.ensure_backup_user).to eq false
    end
  end

  describe 'restore' do
    it 'should be a no-op (not yet implemented)' do
      expect(subject.restore).to eq nil
    end
  end
end