require 'spec_helper'

describe CloudModel::MongodbPatch do
  let(:out) { StringIO.new }
  let(:member_timeout) { 60 }
  subject { described_class.new output: out, lag_limit: 30, member_timeout: member_timeout }

  let(:host) { double CloudModel::Host, name: 'core-a' }
  let(:last_backup) { Time.now - 5.hours }
  let(:set) { double CloudModel::MongodbReplicationSet, name: 'rs-app', service_uris: ['10.0.0.1:27017', '10.0.0.2:27017', '10.0.0.3:27017'], item_issues: issues, has_backups: true, last_successful_backup_at: last_backup }
  before { allow(set).to receive(:services).and_return members }
  let(:issues) { double 'issues', find_or_initialize_by: double('issue', :severity= => nil, :message= => nil, save: true), where: double('scope', update_all: 1) }

  def member_service name, ip, priority: 50, arbiter: false
    guest = double CloudModel::Guest, name: name, host: host, deploy_state: :finished, item_issues: issues
    service = double CloudModel::Services::Mongodb, id: BSON::ObjectId.new, guest: guest, server_uri: "#{ip}:27017",
      mongodb_replication_set: set, mongodb_replication_priority: priority, mongodb_replication_arbiter_only: arbiter
    allow(service).to receive(:is_a?) { |klass| klass == CloudModel::Services::Mongodb }
    service
  end

  let(:primary) { member_service 'mongo-1', '10.0.0.1' }
  let(:secondary) { member_service 'mongo-2', '10.0.0.2', priority: 40 }
  let(:arbiter) { member_service 'mongo-3', '10.0.0.3', priority: 0, arbiter: true }
  let(:members) { [primary, secondary, arbiter] }

  let(:now) { Time.now }
  def status primary_name: '10.0.0.1:27017', lag: 0, down: []
    {
      'ok' => 1.0,
      'members' => [
        { 'name' => '10.0.0.1:27017', 'found' => true, 'health' => down.include?('10.0.0.1:27017') ? 0.0 : 1.0, 'stateStr' => primary_name == '10.0.0.1:27017' ? 'PRIMARY' : 'SECONDARY', 'optimeDate' => now },
        { 'name' => '10.0.0.2:27017', 'found' => true, 'health' => down.include?('10.0.0.2:27017') ? 0.0 : 1.0, 'stateStr' => primary_name == '10.0.0.2:27017' ? 'PRIMARY' : 'SECONDARY', 'optimeDate' => now - lag },
        { 'name' => '10.0.0.3:27017', 'found' => true, 'health' => 1.0, 'stateStr' => 'ARBITER' }
      ]
    }
  end
  let(:config) { { 'members' => [{ 'host' => '10.0.0.1:27017', 'votes' => 1 }, { 'host' => '10.0.0.2:27017', 'votes' => 1 }, { 'host' => '10.0.0.3:27017', 'votes' => 1 }] } }

  def inventory_output installed:, candidate:, update_failed: false
    "#{update_failed ? "update_failed=1\n" : ''}installed=#{installed}\ncandidate=#{candidate}\npackages=mongodb-org mongodb-org-server mongodb-org-tools\n"
  end

  before do
    allow(subject).to receive(:sleep)
    allow(subject).to receive(:own_addresses).and_return []
    allow(set).to receive(:read_config).and_return config
  end

  describe '.services_of' do
    it 'takes the MongoDB services of finished guests and of guests whose redeploy failed, not of one being deployed' do
      mongo = double 'mongo'
      allow(mongo).to receive(:is_a?) { |k| k == CloudModel::Services::Mongodb }
      nginx = double 'nginx'
      allow(nginx).to receive(:is_a?).and_return false
      running = double 'guest', deploy_state: :finished, services: [mongo, nginx]
      failed = double 'guest', deploy_state: :failed, services: [mongo]
      pending = double 'guest', deploy_state: :pending, services: [mongo]
      expect(described_class.services_of([running, failed, pending])).to eq [mongo, mongo]
    end
  end

  describe '#inventory' do
    it 'parses the guest report and asks the running mongod for its version' do
      expect(primary.guest).to receive(:exec).with(/mongodb-org-server/).and_return [true, inventory_output(installed: '7.0.28', candidate: '7.0.48')]
      expect(subject).to receive(:running_version).with(primary).and_return '7.0.28'
      inv = subject.inventory primary
      expect(inv[:installed]).to eq '7.0.28'
      expect(inv[:candidate]).to eq '7.0.48'
      expect(inv[:packages]).to eq %w(mongodb-org mongodb-org-server mongodb-org-tools)
      expect(inv[:running]).to eq '7.0.28'
      expect(subject.behind?(inv)).to be true
    end

    it 'is current when package and running mongod are the candidate, and when there is no candidate' do
      expect(subject.behind?(installed: '7.0.48', candidate: '7.0.48', running: '7.0.48')).to be false
      expect(subject.behind?(installed: '7.0.48', candidate: nil, running: '7.0.48')).to be false
    end

    it 'is behind when the package is new but the running mongod is still the old one' do
      expect(subject.behind?(installed: '7.0.48', candidate: '7.0.48', running: '7.0.28')).to be true
    end

    it 'fails a guest without the server package' do
      expect(primary.guest).to receive(:exec).and_return [true, "installed=\ncandidate=(none)\npackages=\n"]
      expect { subject.inventory primary }.to raise_error(/no mongodb-org-server/)
    end
  end

  describe '#patch!' do
    def stub_inventories versions
      members.each do |service|
        installed = versions.fetch(service.guest.name)
        allow(service.guest).to receive(:exec).with(/mongodb-org-server/).and_return [true, inventory_output(installed: installed, candidate: '7.0.48')]
      end
      allow(subject).to receive(:running_version) { |service| versions.fetch(service.guest.name) }
    end

    it 'refuses a partial set and upgrades nothing' do
      [primary, secondary].each { |s| allow(s.guest).to receive(:exec).and_return [true, inventory_output(installed: '7.0.28', candidate: '7.0.48')] }
      allow(subject).to receive(:running_version).and_return '7.0.28'
      members.each { |s| expect(s.guest).not_to receive(:exec!) }
      counts = subject.patch! [primary, secondary], dry_run: false
      expect(counts).to eq patched: 0, current: 0, skipped: 2, failed: 0, deferred: 0
      expect(out.string).to include '1 member(s) of the set are not in this run: mongo-3 (finished)'
    end

    it 'leaves a set alone that is on the candidate already' do
      stub_inventories 'mongo-1' => '7.0.48', 'mongo-2' => '7.0.48', 'mongo-3' => '7.0.48'
      expect(set).not_to receive(:status)
      counts = subject.patch! members, dry_run: false
      expect(counts).to eq patched: 0, current: 3, skipped: 0, failed: 0, deferred: 0
      expect(out.string).to include 'mongo-1@core-a: on 7.0.48'
    end

    it 'plans arbiter, secondary, primary in the dry run and changes nothing' do
      stub_inventories 'mongo-1' => '7.0.28', 'mongo-2' => '7.0.28', 'mongo-3' => '7.0.28'
      allow(set).to receive(:status).and_return status
      members.each { |s| expect(s.guest).not_to receive(:exec!) }
      counts = subject.patch! members, dry_run: true
      expect(counts).to eq patched: 0, current: 0, skipped: 0, failed: 0, deferred: 0
      expect(out.string).to include 'would patch mongo-3@core-a (ARBITER), mongo-2@core-a (SECONDARY), mongo-1@core-a (PRIMARY), one after the other'
    end

    it 'skips a set with a member down and records an issue on the set' do
      stub_inventories 'mongo-1' => '7.0.28', 'mongo-2' => '7.0.28', 'mongo-3' => '7.0.28'
      allow(set).to receive(:status).and_return status(down: ['10.0.0.2:27017'])
      expect(issues).to receive(:find_or_initialize_by).with(key: :mongodb_patch_blocked, resolved_at: nil)
      counts = subject.patch! members, dry_run: false
      expect(counts[:skipped]).to eq 3
      expect(out.string).to match(/skipped.*: member\(s\) down: 10\.0\.0\.2:27017/)
    end

    it 'skips a set whose lag is over the limit' do
      stub_inventories 'mongo-1' => '7.0.28', 'mongo-2' => '7.0.28', 'mongo-3' => '7.0.28'
      allow(set).to receive(:status).and_return status(lag: 120)
      counts = subject.patch! members, dry_run: false
      expect(counts[:skipped]).to eq 3
      expect(out.string).to include 'replication lag 120s is over the limit of 30s'
    end

    it 'skips a set where a member did not answer the inventory' do
      allow(primary.guest).to receive(:exec).and_return [false, 'Error: Instance not running']
      [secondary, arbiter].each { |s| allow(s.guest).to receive(:exec).and_return [true, inventory_output(installed: '7.0.28', candidate: '7.0.48')] }
      allow(subject).to receive(:running_version).and_return '7.0.28'
      counts = subject.patch! members, dry_run: false
      expect(counts).to eq patched: 0, current: 0, skipped: 2, failed: 1, deferred: 0
      expect(out.string).to include 'not every member answered'
    end

    it 'upgrades arbiter and secondary, steps the primary down first, and waits for each member to come back caught up' do
      versions = { 'mongo-1' => '7.0.28', 'mongo-2' => '7.0.28', 'mongo-3' => '7.0.28' }
      stub_inventories versions
      allow(subject).to receive(:running_version) { |service| versions.fetch(service.guest.name) }
      current_status = status
      allow(set).to receive(:status) { current_status }

      order = []
      members.each do |service|
        allow(service.guest).to receive(:exec!).with(/only-upgrade.*mongodb-org-server/, anything) do
          order << service.guest.name
          versions[service.guest.name] = '7.0.48'
          ''
        end
      end
      primary_now = true
      allow(subject).to receive(:member_role).with(primary) { { set: 'rs-app', primary: primary_now, member: true } }
      expect(subject).to receive(:direct_command).with(primary, hash_including(replSetStepDown: 60)) do
        current_status = status(primary_name: '10.0.0.2:27017')
        primary_now = false
        {}
      end

      counts = subject.patch! members, dry_run: false
      expect(counts).to eq patched: 3, current: 0, skipped: 0, failed: 0, deferred: 0
      expect(order).to eq %w(mongo-3 mongo-2 mongo-1)
      expect(out.string).to include 'mongo-1@core-a: primary, stepping down'
      expect(out.string.scan(/patched.* to 7\.0\.48/).size).to eq 3
    end

    context 'when a member does not come back' do
    let(:member_timeout) { 0 }

    it 'restarts mongod itself when the package did not, and stops with the set' do
      versions = { 'mongo-1' => '7.0.28', 'mongo-2' => '7.0.28', 'mongo-3' => '7.0.28' }
      stub_inventories versions
      allow(subject).to receive(:running_version) { |service| versions.fetch(service.guest.name) }
      allow(set).to receive(:status).and_return status
      allow(arbiter.guest).to receive(:exec!).with(/only-upgrade/, anything).and_return ''
      expect(arbiter.guest).to receive(:exec!).with('/bin/systemctl restart mongod', anything) do
        versions['mongo-3'] = '7.0.48'
        ''
      end
      # the arbiter comes back on the release; the secondary never does
      allow(secondary.guest).to receive(:exec!).with(/only-upgrade/, anything).and_return ''
      allow(secondary.guest).to receive(:exec!).with('/bin/systemctl restart mongod', anything).and_return ''
      expect(primary.guest).not_to receive(:exec!)
      expect(issues).to receive(:find_or_initialize_by).with(key: :mongodb_patch, resolved_at: nil)

      counts = subject.patch! members, dry_run: false
      expect(counts[:patched]).to eq 1
      expect(counts[:failed]).to eq 1
      expect(out.string).to include 'stopping with this set'
    end
    end

    it 'refuses to take a member down when the set would lose its majority' do
      stub_inventories 'mongo-1' => '7.0.28', 'mongo-2' => '7.0.28', 'mongo-3' => '7.0.48'
      members.each { |s| expect(s.guest).not_to receive(:exec!) }
      allow(set).to receive(:read_config).and_return('members' => [{ 'host' => '10.0.0.1:27017', 'votes' => 1 }, { 'host' => '10.0.0.2:27017', 'votes' => 1 }, { 'host' => '10.0.0.3:27017', 'votes' => 0 }])
      allow(set).to receive(:status).and_return status
      # with two voting members, taking either down leaves one of two — no majority
      counts = subject.patch! members, dry_run: false
      expect(counts).to eq patched: 0, current: 1, skipped: 2, failed: 0, deferred: 0
      expect(out.string).to include 'no majority'
    end

    it 'upgrades a standalone service and waits for the new version' do
      guest = double CloudModel::Guest, name: 'web', host: host, deploy_state: :finished, item_issues: issues
      service = double CloudModel::Services::Mongodb, id: BSON::ObjectId.new, guest: guest, server_uri: '10.0.0.9:27017', mongodb_replication_set: nil, has_backups: true, last_successful_backup_at: last_backup
      allow(guest).to receive(:exec).and_return [true, inventory_output(installed: '7.0.28', candidate: '7.0.48')]
      running = '7.0.28'
      allow(subject).to receive(:running_version) { running }
      allow(subject).to receive(:direct_command).with(service, hello: 1).and_return('isWritablePrimary' => true)
      expect(guest).to receive(:exec!).with(/only-upgrade/, anything) { running = '7.0.48'; '' }
      counts = subject.patch! [service], dry_run: false
      expect(counts).to eq patched: 1, current: 0, skipped: 0, failed: 0, deferred: 0
      expect(out.string).to include 'standalone — restarts'
      expect(out.string).to match(/web@core-a: .*patched.* to 7\.0\.48/)
    end

    it 'steps a primary down whose set the admin does not know, and waits until it is a member again' do
      guest = double CloudModel::Guest, name: 'admin', host: host, deploy_state: :finished, item_issues: issues
      service = double CloudModel::Services::Mongodb, id: BSON::ObjectId.new, guest: guest, server_uri: '10.0.0.8:27017', mongodb_replication_set: nil, has_backups: true, last_successful_backup_at: last_backup
      allow(guest).to receive(:exec).and_return [true, inventory_output(installed: '7.0.28', candidate: '7.0.48')]
      running = '7.0.28'
      primary = true
      allow(subject).to receive(:running_version) { running }
      allow(subject).to receive(:direct_command).with(service, hello: 1) { { 'setName' => 'admin', 'isWritablePrimary' => primary, 'secondary' => !primary } }
      expect(subject).to receive(:direct_command).with(service, hash_including(replSetStepDown: 60)) { primary = false; {} }
      expect(guest).to receive(:exec!).with(/only-upgrade/, anything) { running = '7.0.48'; '' }
      counts = subject.patch! [service], dry_run: false
      expect(counts).to eq patched: 1, current: 0, skipped: 0, failed: 0, deferred: 0
      expect(out.string).to include 'member of the unmanaged replica set admin, primary — steps down first'
      expect(out.string).to include 'admin@core-a: primary, stepping down'
    end

    it 'blocks a set whose status cannot be read instead of crashing' do
      stub_inventories 'mongo-1' => '7.0.28', 'mongo-2' => '7.0.28', 'mongo-3' => '7.0.28'
      allow(set).to receive(:status).and_raise RuntimeError, 'Previous reconfig has not been committed yet'
      counts = subject.patch! members, dry_run: false
      expect(counts[:skipped]).to eq 3
      expect(out.string).to include 'replica set status unavailable (RuntimeError: Previous reconfig'
    end
  end

  describe 'the backup rule and the deadline' do
    before { stub_all 'mongo-1' => '7.0.28', 'mongo-2' => '7.0.28', 'mongo-3' => '7.0.28' }

    def stub_all versions
      members.each do |service|
        allow(service.guest).to receive(:exec).with(/mongodb-org-server/).and_return [true, inventory_output(installed: versions.fetch(service.guest.name), candidate: '7.0.48')]
      end
      allow(subject).to receive(:running_version) { |service| versions.fetch(service.guest.name) }
      allow(set).to receive(:status).and_return status
    end

    it 'skips a set without a configured backup and records it on the set' do
      allow(set).to receive(:has_backups).and_return false
      expect(issues).to receive(:find_or_initialize_by).with(key: :mongodb_patch_blocked, resolved_at: nil)
      counts = subject.patch! members, dry_run: false
      expect(counts[:skipped]).to eq 3
      expect(out.string).to include 'no backup configured'
    end

    context 'with a backup older than the limit' do
      let(:last_backup) { Time.now - 40.hours }

      it 'skips the set' do
        counts = subject.patch! members, dry_run: false
        expect(counts[:skipped]).to eq 3
        expect(out.string).to match(/last successful backup .* is older than 36 h/)
      end
    end

    it 'patches without the backup rule when told to' do
      allow(set).to receive(:has_backups).and_return false
      patch = described_class.new output: out, member_timeout: 60, require_backup: false
      allow(patch).to receive(:running_version).and_return '7.0.28'
      counts = patch.patch! members, dry_run: true
      expect(counts[:skipped]).to eq 0
      expect(out.string).to include 'would patch'
    end

    it 'defers every set after the deadline instead of starting it' do
      patch = described_class.new output: out, member_timeout: 60, deadline: Time.now - 60
      allow(patch).to receive(:running_version).and_return '7.0.28'
      members.each { |s| expect(s.guest).not_to receive(:exec!) }
      counts = patch.patch! members, dry_run: false
      expect(counts).to eq patched: 0, current: 0, skipped: 0, failed: 0, deferred: 3
      expect(out.string).to include 'deferred'
      expect(out.string).to include 'left for the next night'
    end
  end

  describe '.deadline_today' do
    it 'is the given UTC time on the day of now' do
      now = Time.utc(2026, 11, 24, 0, 5)
      expect(described_class.deadline_today('02:00', now)).to eq Time.utc(2026, 11, 24, 2, 0)
    end
  end

  describe '.nightly!' do
    it 'does nothing when switched off' do
      allow(CloudModel.config).to receive(:mongodb_unattended).and_return false
      expect(described_class).not_to receive(:new)
      expect(described_class.nightly!(output: out)).to be_nil
      expect(out.string).to include 'switched off'
    end

    it 'does nothing outside the window' do
      allow(CloudModel.config).to receive(:mongodb_unattended).and_return true
      expect(described_class).not_to receive(:new)
      expect(described_class.nightly!(output: out, now: Time.utc(2026, 11, 24, 10, 15))).to be_nil
      expect(out.string).to include 'between 00:00 and 02:00 UTC only'
    end

    it 'never raises' do
      allow(CloudModel.config).to receive(:mongodb_unattended).and_return true
      allow(CloudModel::Guest).to receive(:all).and_raise 'db gone'
      allow(CloudModel).to receive(:log_exception)
      expect(described_class.nightly!(output: out, now: Time.utc(2026, 11, 24, 0, 5))).to be_nil
      expect(out.string).to include 'crashed'
    end
  end
end
