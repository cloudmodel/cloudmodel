# encoding: UTF-8

require 'spec_helper'

describe CloudModel::LxdCustomVolume do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:name).of_type(String) }
  it { expect(subject).to have_field(:pool).of_type(String).with_default_value_of 'default' }
  it { expect(subject).to have_field(:disk_space).of_type(Integer).with_default_value_of 10*1024*1024*1024 }
  it { expect(subject).to have_field(:mount_point).of_type(String) }
  it { expect(subject).to have_field(:writeable).of_type(Mongoid::Boolean).with_default_value_of true }
  it { expect(subject).to have_field(:has_backups).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:backups_enabled_at).of_type(Time) }

  it { expect(subject).to be_embedded_in(:guest).of_type CloudModel::Guest }

  describe 'track_backups_enabled_at' do
    it 'stamps backups_enabled_at when backups get enabled' do
      allow(subject).to receive(:has_backups_changed?).and_return true
      allow(subject).to receive(:has_backups?).and_return true
      subject.send :track_backups_enabled_at
      expect(subject.backups_enabled_at).to be_within(5).of(Time.now)
    end

    it 'clears backups_enabled_at when backups get disabled' do
      subject.backups_enabled_at = Time.now
      allow(subject).to receive(:has_backups_changed?).and_return true
      allow(subject).to receive(:has_backups?).and_return false
      subject.send :track_backups_enabled_at
      expect(subject.backups_enabled_at).to be_nil
    end

    it 'leaves backups_enabled_at unchanged when has_backups did not change' do
      subject.backups_enabled_at = nil
      allow(subject).to receive(:has_backups_changed?).and_return false
      subject.send :track_backups_enabled_at
      expect(subject.backups_enabled_at).to be_nil
    end
  end

  it { expect(subject).to validate_presence_of(:mount_point) }
  it { expect(subject).to validate_uniqueness_of(:mount_point).scoped_to(:guest) }
  it { expect(subject).to validate_format_of(:mount_point).to_allow 'var/data' }
  it { expect(subject).to validate_format_of(:mount_point).not_to_allow '/var/data' }
  it { expect(subject).to validate_format_of(:mount_point).not_to_allow 'var/this data' }

  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name).scoped_to(:host) }
  it { expect(subject).to validate_format_of(:name).to_allow 'some_guest-var-data' }
  it { expect(subject).to validate_format_of(:name).not_to_allow '-var-data' }
  it { expect(subject).to validate_format_of(:name).not_to_allow 'some_guest-var/data' }

  let(:host) { Factory :host }
  let(:guest) { Factory :guest, name: 'some_guest', host: host }

  describe 'host' do
    it 'should return guest´s host' do
      subject.guest = guest
      expect(subject.host).to eq host
    end
  end

  describe 'before_destroy' do
    it 'should not allow to destroy used volumes' do
      allow(subject).to receive(:used?).and_return true

      expect do
        expect(subject.before_destroy).to eq false
      end.to output("Can't destroy attached volume; unattach it first\n").to_stdout
    end

    it 'should not allow to destroy not used volumes, which are not able to be deleted' do
      allow(subject).to receive(:used?).and_return false
      allow(subject).to receive(:destroy_volume).and_return [false, '']

      expect do
        expect(subject.before_destroy).to eq false
      end.to output("Failed to destroy LXD volume\n").to_stdout
    end

    it 'should allow to destroy not used volumes, which are able to be deleted' do
      allow(subject).to receive(:used?).and_return false
      allow(subject).to receive(:destroy_volume).and_return [true, '']

      expect(subject.before_destroy).to eq true
    end

    it 'should be called on destroy' do
      expect(subject).to receive(:before_destroy)

      subject.run_callbacks :destroy
    end

    it 'should not be called on destroy if :skip_volume_creation is set' do
      expect(subject).not_to receive :before_destroy
      subject.skip_volume_creation = true

      subject.run_callbacks :destroy
    end
  end

  describe 'volume_exists?' do
    it 'should return true if lxd volume has valid info' do
      subject.name = 'some_guest-var-data'
      allow(subject).to receive(:lxc).with('storage volume show default some_guest-var-data').and_return [true, '']

      expect(subject.volume_exists?).to eq true
    end

    it 'should return false if lxd volume has not found error' do
      subject.name = 'some_guest-var-data'
      allow(subject).to receive(:lxc).with('storage volume show default some_guest-var-data').and_return [false, "Error: not found\n"]

      expect(subject.volume_exists?).to eq false
    end

    it 'should return true if lxd volume has not found error (assuming it exists otherwise)' do
      subject.name = 'some_guest-var-data'
      allow(subject).to receive(:lxc).with('storage volume show default some_guest-var-data').and_return [false, "\n\nError: Something else\n"]

      expect(subject.volume_exists?).to eq true
    end

    it 'should use diffent pool' do
      subject.pool = 'data'
      subject.name = 'some_guest-var-large-data'
      allow(subject).to receive(:lxc).with('storage volume show data some_guest-var-large-data').and_return [true, '']

      expect(subject.volume_exists?).to eq true
    end

    it 'should escape pool and name' do
      subject.pool = 'data; rm -rf'
      subject.name = 'some_guest-var-large-data|killall sshd'
      allow(subject).to receive(:lxc).with('storage volume show data\\;\\ rm\\ -rf some_guest-var-large-data\\|killall\\ sshd').and_return [true, '']

      expect(subject.volume_exists?).to eq true
    end
  end

  describe 'create_volume' do
    it 'should call lxd to create volume' do
      subject.name = 'some_guest-var-data'
      expect(subject).to receive(:lxc).with('storage volume create default some_guest-var-data')

      subject.create_volume
    end

    it 'should use diffent pool' do
      subject.pool = 'data'
      subject.name = 'some_guest-var-large-data'
      allow(subject).to receive(:lxc).with('storage volume create data some_guest-var-large-data').and_return [true, '']

      subject.create_volume
    end

    it 'should escape pool and name' do
      subject.pool = 'data; rm -rf'
      subject.name = 'some_guest-var-large-data|killall sshd'
      allow(subject).to receive(:lxc).with('storage volume create data\\;\\ rm\\ -rf some_guest-var-large-data\\|killall\\ sshd').and_return [true, '']

      subject.create_volume
    end
  end

  describe 'create_volume!' do
    it 'should call lxd to create volume' do
      allow(guest).to receive(:deploy_state).and_return(:finished)
      subject.guest = guest
      subject.name = 'some_guest-var-data'
      expect(subject).to receive(:lxc!).with('storage volume create default some_guest-var-data', 'Failed to init LXD volume')

      subject.create_volume!
    end

    it 'should use diffent pool' do
      allow(guest).to receive(:deploy_state).and_return(:finished)
      subject.guest = guest
      subject.pool = 'data'
      subject.name = 'some_guest-var-large-data'
      allow(subject).to receive(:lxc!).with('storage volume create data some_guest-var-large-data', "Failed to init LXD volume").and_return [true, '']

      subject.create_volume!
    end

    it 'should escape pool and name' do
      allow(guest).to receive(:deploy_state).and_return(:finished)
      subject.guest = guest
      subject.pool = 'data; rm -rf'
      subject.name = 'some_guest-var-large-data|killall sshd'
      allow(subject).to receive(:lxc!).with('storage volume create data\\;\\ rm\\ -rf some_guest-var-large-data\\|killall\\ sshd', "Failed to init LXD volume").and_return [true, '']

      subject.create_volume!
    end

    it 'should not call lxd to create volume if guest was never deployed (not started deploy state)' do
      allow(guest).to receive(:deploy_state).and_return(:not_started)
      subject.guest = guest
      subject.name = 'some_guest-var-data'
      expect(subject).not_to receive(:lxc!)

      subject.create_volume!
    end

    it 'should be called on create' do
      expect(subject).to receive :create_volume!

      subject.run_callbacks :create
    end

    it 'should not be called on create if :skip_volume_creation is set' do
      expect(subject).not_to receive :create_volume!
      subject.skip_volume_creation = true

      subject.run_callbacks :create
    end
  end

  describe 'destroy_volume' do
    it 'should call lxd to destroy volume' do
      subject.name = 'some_guest-var-data'
      expect(subject).to receive(:lxc).with('storage volume delete default some_guest-var-data')

      subject.destroy_volume
    end

    it 'should use diffent pool' do
      subject.pool = 'data'
      subject.name = 'some_guest-var-large-data'
      allow(subject).to receive(:lxc).with('storage volume delete data some_guest-var-large-data').and_return [true, '']

      subject.destroy_volume
    end

    it 'should escape pool and name' do
      subject.pool = 'data; rm -rf'
      subject.name = 'some_guest-var-large-data|killall sshd'
      allow(subject).to receive(:lxc).with('storage volume delete data\\;\\ rm\\ -rf some_guest-var-large-data\\|killall\\ sshd').and_return [true, '']

      subject.destroy_volume
    end
  end

  describe 'to_param' do
    it 'should return name as param' do
      subject.name = 'some_guest-var-data'
      expect(subject.to_param).to eq 'some_guest-var-data'
    end
  end

  describe 'item_issue_chain' do
    it 'should return chained items to volume for ItemIssue' do
      subject.guest = guest

      expect(subject.item_issue_chain).to eq [host, guest, subject]
    end
  end

  describe 'lxc_show' do
    it 'should call lxd show and parse returned yaml' do
      subject.name = 'some_guest-var-data'

      expect(subject).to receive(:lxc).with('storage volume show default some_guest-var-data').and_return [
        true,
        <<~YAML
          test_data:
            value: something
        YAML
      ]

      expect(subject.lxc_show).to eq 'test_data' => {'value' => 'something'}
    end

    it 'should use diffent pool' do
      subject.pool = 'data'
      subject.name = 'some_guest-var-large-data'
      allow(subject).to receive(:lxc).with('storage volume show data some_guest-var-large-data').and_return [
        true,
        <<~YAML
          test_data:
            value: something with data storage pool
        YAML
      ]

      expect(subject.lxc_show).to eq 'test_data' => {'value' => 'something with data storage pool'}
    end

    it 'should escape pool and name' do
      subject.pool = 'data; rm -rf'
      subject.name = 'some_guest-var-large-data|killall sshd'
      allow(subject).to receive(:lxc).with('storage volume show data\\;\\ rm\\ -rf some_guest-var-large-data\\|killall\\ sshd').and_return [
        true,
        <<~YAML
          test_data:
            value: something with malicious
        YAML
      ]

      expect(subject.lxc_show).to eq 'test_data' => {'value' => 'something with malicious'}
    end

    it 'should return nil if lxc show fails' do
      subject.name = 'some_guest-var-data'

      expect(subject).to receive(:lxc).with('storage volume show default some_guest-var-data').and_return [false, 'FATAL ERROR!']

      expect(subject.lxc_show).to eq "error"=>"No valid YAML: FATAL ERROR!"
    end
  end

  describe 'used?' do
    it 'should return true if lxc_show contains used_by' do
      allow(subject).to receive(:lxc_show).and_return 'used_by' => ['a', 'b']

      expect(subject.used?).to eq true
    end

    it 'should return false if lxc_show does contain empty used_by' do
      allow(subject).to receive(:lxc_show).and_return 'used_by' => []

      expect(subject.used?).to eq false
    end

    it 'should return nil if lxc_show does not contain used_by' do
      allow(subject).to receive(:lxc_show).and_return({})

      expect(subject.used?).to eq nil
    end

    it 'should return nil if lxc_show is nil' do
      allow(subject).to receive(:lxc_show).and_return nil

      expect(subject.used?).to eq nil
    end
  end

  describe 'usage_bytes' do
    it 'should return used bytes from df monitoring data' do
      subject.guest = guest
      subject.name = 'test-vol'
      subject.pool = 'default'
      allow(guest).to receive(:monitoring_last_check_result).and_return({
        'system' => {'df' => {:"guests/custom/test-vol" => {'used' => '1024'}}}
      })

      expect(subject.usage_bytes).to eq 1024 * 1024
    end

    it 'should return nil when no monitoring data' do
      subject.guest = guest
      allow(guest).to receive(:monitoring_last_check_result).and_return(nil)

      expect(subject.usage_bytes).to eq nil
    end
  end

  describe 'usage_percentage' do
    it 'should calculate percentage usage' do
      allow(subject).to receive(:usage_bytes).and_return 26625
      subject.disk_space = 65536

      expect(subject.usage_percentage).to eq 40.62652587890625

      allow(subject).to receive(:usage_bytes).and_return 256
      subject.disk_space = 512

      expect(subject.usage_percentage).to eq 50.0
    end
  end

  describe 'host_path' do
    it 'should return path to volume mount on host' do
      subject.name = 'some_guest-var-data'
      expect(subject.host_path).to eq '/var/lib/lxd/storage-pools/default/custom/some_guest-var-data/'
    end
  end

  describe 'backup_directory' do
    it 'should return path to backups on backup system' do
      subject.guest = guest
      subject.name = 'some_guest-var-data'
      allow(CloudModel.config).to receive(:backup_directory).and_return '/var/cloudmodel_backups'

      expect(subject.backup_directory).to eq "/var/cloudmodel_backups/#{host.id}/#{guest.id}/volumes/#{subject.id}"
    end
  end

  describe 'zfs_dataset' do
    before do
      subject.guest = guest
      subject.name = 'some_guest-var-data'
      subject.pool = 'default'
    end

    it 'should resolve the default_-prefixed custom volume dataset' do
      allow(host).to receive(:exec).with('zfs list -H -o name -t filesystem').and_return(
        [true, "guests\nguests/custom/default_some_guest-var-data\nguests/containers/x\n"]
      )
      expect(subject.zfs_dataset).to eq 'guests/custom/default_some_guest-var-data'
    end

    it 'should fall back to the unprefixed dataset name' do
      allow(host).to receive(:exec).with('zfs list -H -o name -t filesystem').and_return(
        [true, "guests/custom/some_guest-var-data\n"]
      )
      expect(subject.zfs_dataset).to eq 'guests/custom/some_guest-var-data'
    end

    it 'should be nil when no matching dataset exists' do
      allow(host).to receive(:exec).with('zfs list -H -o name -t filesystem').and_return([true, "guests/other\n"])
      expect(subject.zfs_dataset).to be_nil
    end
  end

  describe 'last_backup_at' do
    let(:dataset) { 'guests/custom/default_some_guest-var-data' }

    before do
      subject.guest = guest
      allow(subject).to receive(:zfs_dataset).and_return(dataset)
    end

    it 'should return the time of the newest backup snapshot' do
      allow(subject).to receive(:zfs_backup_snapshots).and_return(["#{dataset}@coreon-bkp-20200403133742"])
      expect(subject.last_backup_at).to eq Time.strptime('20200403133742', '%Y%m%d%H%M%S')
    end

    it 'should be nil when there are no backup snapshots' do
      allow(subject).to receive(:zfs_backup_snapshots).and_return([])
      expect(subject.last_backup_at).to be_nil
    end
  end

  describe 'backup' do
    let(:dataset) { 'guests/custom/default_some_guest-var-data' }
    let(:backup_host) { double 'backup_host', private_address: '10.42.0.9' }

    before do
      subject.has_backups = true
      subject.guest = guest
      allow(subject).to receive(:zfs_dataset).and_return(dataset)
      allow(subject).to receive(:backup_root_dataset).and_return('data/admin-backups')
      allow(CloudModel::Host).to receive(:local).and_return(backup_host)
      allow(backup_host).to receive(:exec).and_return([true, ''])
      allow(host).to receive(:private_address).and_return('10.42.0.1')
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(Rails.logger).to receive(:debug)
      allow(Rails.logger).to receive(:error)
      allow(subject).to receive(:`) { `true`; '' } # the send | receive pipe
    end

    it 'should return false if has_backups is false' do
      subject.has_backups = false
      expect(subject.backup).to eq false
    end

    it 'should return false when no source dataset can be resolved' do
      allow(subject).to receive(:zfs_dataset).and_return(nil)
      expect(subject.backup).to eq false
    end

    it 'should return false when the backup target cannot be resolved' do
      allow(subject).to receive(:backup_root_dataset).and_return(nil)
      expect(subject.backup).to eq false
    end

    it 'should snapshot, send full and prune on first run' do
      allow(subject).to receive(:zfs_backup_snapshots).and_return([]) # no base -> full send
      expect(host).to receive(:exec).with(/\Azfs snapshot #{dataset}@coreon-bkp-[0-9]{14}\z/).and_return([true, ''])
      expect(subject).to receive(:send_to_backup_host).with(/#{dataset}@coreon-bkp-/, nil, %r{\Adata/admin-backups/zfs_backups/}).and_return(true)
      allow(subject).to receive(:prune_source_snapshots)
      allow(subject).to receive(:prune_target_snapshots)

      expect(subject.backup).to eq true
    end

    it 'should send incrementally against the newest existing snapshot' do
      base = "#{dataset}@coreon-bkp-20240101000000"
      allow(subject).to receive(:zfs_backup_snapshots).and_return([base])
      allow(host).to receive(:exec).and_return([true, ''])
      expect(subject).to receive(:send_to_backup_host).with(anything, base, anything).and_return(true)
      allow(subject).to receive(:prune_source_snapshots)
      allow(subject).to receive(:prune_target_snapshots)

      expect(subject.backup).to eq true
    end

    it 'should destroy the snapshot and return false when the transfer fails' do
      allow(subject).to receive(:zfs_backup_snapshots).and_return([])
      allow(host).to receive(:exec).and_return([true, ''])
      allow(subject).to receive(:send_to_backup_host).and_return(false)

      expect(host).to receive(:exec).with(/\Azfs destroy /).and_return([true, ''])
      expect(subject.backup).to eq false
    end
  end

  describe 'restore' do
    let(:dataset) { 'guests/custom/default_some_guest-var-data' }
    let(:backup_host) { double 'backup_host', private_address: '10.42.0.9' }
    let(:target) { 'data/admin-backups/zfs_backups/h/g/v' }

    it 'should send the latest snapshot from the backup host onto the source' do
      subject.guest = guest
      allow(subject).to receive(:zfs_dataset).and_return(dataset)
      allow(subject).to receive(:backup_target_dataset).and_return(target)
      allow(subject).to receive(:backup_host).and_return(backup_host)
      allow(host).to receive(:private_address).and_return('10.42.0.1')
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(Rails.logger).to receive(:debug)
      allow(backup_host).to receive(:exec).with(/zfs list .*-t snapshot/).and_return(
        [true, "#{target}@coreon-bkp-20240101000000\n#{target}@coreon-bkp-20240102000000\n"]
      )
      allow(subject).to receive(:`) { `true`; '' }

      expect(subject.restore(force: true)).to eq true
    end

    it 'refuses to restore without force' do
      expect { subject.restore }.to raise_error(CloudModel::BackupError, /force: true/)
    end
  end

  describe 'take_consistent_snapshot' do
    it 'wraps the snapshot in the owning service backup consistency' do
      subject.guest = guest
      subject.mount_point = 'var/lib/mongodb'
      svc = double 'mongo', backup_data_mount_point: 'var/lib/mongodb'
      allow(guest).to receive(:services).and_return([svc])
      allow(host).to receive(:exec).with(/zfs snapshot/).and_return([true, ''])

      expect(svc).to receive(:with_backup_consistency).and_yield.and_return(true)
      expect(subject.send(:take_consistent_snapshot, 'ds@snap')).to eq true
    end

    it 'snapshots directly when no service owns the volume' do
      subject.guest = guest
      subject.mount_point = 'var/data'
      allow(guest).to receive(:services).and_return([])
      expect(host).to receive(:exec).with(/zfs snapshot/).and_return([true, ''])

      expect(subject.send(:take_consistent_snapshot, 'ds@snap')).to eq true
    end
  end

  describe 'set_volume_name' do
    it 'should set name according to guest name and mountpoint' do
      subject.guest = guest
      subject.mount_point = 'var/data'

      subject.send :set_volume_name
      expect(subject.name).to eq 'some_guest-var-data'
    end

    it 'should be called on validation' do
      expect(subject).to receive :set_volume_name

      subject.run_callbacks :validation
    end
  end

  describe 'lxc' do
    it 'should call lxc on guest´s host' do
      subject.guest = guest
      expect(host).to receive(:exec).with('lxc lxc_command')
      subject.send :lxc, 'lxc_command'
    end
  end

  describe 'lxc!' do
    it 'should call lxc on guest´s host' do
      subject.guest = guest
      expect(host).to receive(:exec!).with('lxc lxc_command', 'There was an error')
      subject.send :lxc!, 'lxc_command', 'There was an error'
    end
  end
end