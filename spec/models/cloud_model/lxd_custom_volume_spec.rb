# encoding: UTF-8

require 'spec_helper'

describe CloudModel::LxdCustomVolume do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:name).of_type(String) }
  it { expect(subject).to have_field(:disk_space).of_type(Integer).with_default_value_of 10*1024*1024*1024 }
  it { expect(subject).to have_field(:mount_point).of_type(String) }
  it { expect(subject).to have_field(:writeable).of_type(Mongoid::Boolean).with_default_value_of true }
  it { expect(subject).to have_field(:has_backups).of_type(Mongoid::Boolean).with_default_value_of false }

  it { expect(subject).to be_embedded_in(:guest).of_type CloudModel::Guest }

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
  end

  describe 'create_volume' do
    it 'should call lxd to create volume' do
      subject.name = 'some_guest-var-data'
      expect(subject).to receive(:lxc).with('storage volume create default some_guest-var-data')

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

  describe 'backup' do
    pending
  end

  describe 'restore' do
    pending
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