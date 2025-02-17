# encoding: UTF-8

require 'spec_helper'

describe CloudModel::LxdContainer do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to be_embedded_in(:guest).of_type CloudModel::Guest }
  it { expect(subject).to belong_to(:guest_template).of_type CloudModel::GuestTemplate }

  let(:host) { Factory :host }
  let(:guest) { Factory :guest, name: 'some_guest', host: host }
  let(:template) { Factory :guest_template }

  before do
    subject.guest = guest
    allow(host).to receive(:exec)
  end

  describe 'before_destroy' do
    it 'should prevent destroy if container is running' do
      allow(subject).to receive(:running?).and_return true
      expect do
        expect(subject.before_destroy).to eq false
      end.to output("Can't destroy running container; stop it first\n").to_stdout
    end

    it 'should be called when container is destroyed' do
      expect(subject).to receive(:before_destroy)
      subject.run_callbacks :destroy
    end
  end

  describe 'host' do
    it 'should return host of guest' do
      subject.guest = guest

      expect(subject.host).to eq host
    end
  end

  describe 'name' do
    it 'should give the lxc name of the container' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time

      expect(subject.name).to eq 'some_guest-20200331133742'
    end

    it 'should use utc time for making name' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      begin
        Time.zone = "Berlin"
        expect(subject.name).to eq 'some_guest-20200331133742'
      ensure
        Time.zone = "UTC"
      end
    end
  end

  describe 'lxc' do
    it 'should call lxc on guest´s host' do
      expect(host).to receive(:exec).with('echo "lxc lxc_command" | bash')
      subject.lxc 'lxc_command'
    end
  end

  describe 'lxc!' do
    it 'should call lxc on guest´s host' do
      expect(host).to receive(:exec!).with('echo "lxc lxc_command" | bash', 'There was an error')
      subject.lxc! 'lxc_command', 'There was an error'
    end
  end

  describe 'ensure_template_is_set' do
    it 'should set guest template from guest' do
      allow(guest).to receive(:template).and_return template

      subject.ensure_template_is_set

      expect(subject.guest_template).to eq template
    end

    it 'should update guest template from guest if container persisted' do
      allow(guest).to receive(:template).and_return template
      allow(subject).to receive(:persisted?).and_return true

      expect(subject).to receive(:update_attribute).with(:guest_template, template)

      subject.ensure_template_is_set
    end

    it 'should be called before validation' do
      expect(subject).to receive :ensure_template_is_set
      subject.run_callbacks :validation
    end
  end

  describe 'import_template' do
    it 'should ensure template and call lxc image import' do
      subject.guest_template = template
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time

      expect(subject).to receive(:ensure_template_is_set)
      expect(subject).to receive(:lxc).with("image import #{template.lxd_image_metadata_tarball} #{template.tarball} --alias #{template.lxd_alias}")

      expect(subject.import_template).to eq true
    end
  end

  describe 'create_container' do
    it 'should call lxc create' do
      subject.guest_template = template
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time

      expect(subject).to receive(:lxc!).with("init #{template.template_type.id}/#{template.id} some_guest-20200331133742", 'Failed to init LXD container')

      subject.create_container
    end

    it 'should be called when container is created' do
      expect(subject).to receive(:create_container)
      subject.run_callbacks :create
    end
  end

  describe 'destroy_container' do
    it 'should call lxc delete' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time

      expect(subject).to receive(:lxc).with("delete some_guest-20200331133742")

      subject.destroy_container
    end

    it 'should be called when container is destroyed' do
      expect(subject).to receive(:destroy_container)
      subject.run_callbacks :destroy
    end
  end

  describe 'start' do
    before do
      allow(guest).to receive(:update_attributes)
    end

    it 'should call lxc start' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time

      expect(guest).to receive(:lxd_containers).and_return []
      expect(subject).to receive(:lxc).with("start some_guest-20200331133742").and_return [true, '']

      subject.start
    end

    it 'should set guest´s upstate to :started on successful start' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time

      expect(guest).to receive(:lxd_containers).and_return []
      expect(subject).to receive(:lxc).with("start some_guest-20200331133742").and_return [true, '']
      expect(guest).to receive(:update_attributes).with(up_state: :started)

      subject.start
    end

    it 'should set guest´s upstate to :started on successful start' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      time_now = Time.now

      allow(Time).to receive(:now).and_return time_now
      expect(guest).to receive(:lxd_containers).and_return []
      expect(subject).to receive(:lxc).with("start some_guest-20200331133742").and_return [false, 'Ooops, I can´t do it again!']
      expect(guest).to receive(:update_attributes).with(
        last_downtime_at: time_now,
        last_downtime_reason: "LXC start issue: Ooops, I can´t do it again!",
        up_state: :start_failed
      )

      subject.start
    end

    it 'should stop other guest´s containers' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time

      container1 = double
      container2 = double
      expect(container1).to receive(:stop).with(up_state: :booting, reason: 'Reboot')
      expect(container2).to receive(:stop).with(up_state: :booting, reason: 'Reboot')

      expect(guest).to receive(:lxd_containers).and_return [container1, container2]
      expect(subject).to receive(:lxc).with("start some_guest-20200331133742").and_return [true, '']

      subject.start
    end
  end

  describe 'stop' do
    before do
      allow(guest).to receive(:update_attributes)
    end

    it 'should call lxc stop' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      time_now = Time.now
      allow(Time).to receive(:now).and_return time_now

      allow(subject).to receive(:running?).and_return true
      expect(guest).to receive(:update_attributes).with(
        last_downtime_at: time_now,
        last_downtime_reason: "Stopped",
        up_state: :stopped
      )
      expect(subject).to receive(:lxc).with("stop some_guest-20200331133742 -f --timeout=10").and_return [true, '']

      subject.stop
    end

    it 'should call lxc stop with given reason' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      time_now = Time.now
      allow(Time).to receive(:now).and_return time_now

      allow(subject).to receive(:running?).and_return true
      expect(guest).to receive(:update_attributes).with(
        last_downtime_at: time_now,
        last_downtime_reason: "This was intentional",
        up_state: :not_deployed_yet
      )
      expect(subject).to receive(:lxc).with("stop some_guest-20200331133742 -f --timeout=10").and_return [true, '']

      subject.stop reason: 'This was intentional', up_state: :not_deployed_yet
    end

    it 'should not call lxc stop if container not running' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      allow(subject).to receive(:running?).and_return false
      expect(guest).not_to receive(:update_attributes)
      expect(subject).not_to receive(:lxc).with("stop some_guest-20200331133742 -f --timeout=10")

      subject.stop
    end
    it 'should call lxc stop if container not running, but option is force' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      allow(subject).to receive(:running?).and_return false

      expect(subject).to receive(:lxc).with("stop some_guest-20200331133742 -f --timeout=10").and_return [true, '']

      subject.stop force: true
    end
  end

  describe 'mount' do
    it 'should mount zfs container´s fs' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      expect(host).to receive(:exec!).with('zfs mount guests/containers/some_guest-20200331133742', "Failed to mount containers fs")

      subject.mount
    end
  end

  describe 'unmount' do
    it 'should unmount zfs container´s fs' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      expect(host).to receive(:exec).with('zfs unmount guests/containers/some_guest-20200331133742')

      subject.unmount
    end

  end

  describe 'mountpoint' do
    it 'should return the container´s mountpoint in host' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time

      expect(host).to receive(:exec).with("zfs list | grep guests/containers/some_guest-20200331133742").and_return [
        true,
        "guests/containers/some_guest-2020033113374    530M   725G   530M  /var/lib/lxd/storage-pools/default/containers/some_guest-20200331133742\n"
      ]

      subject.mountpoint
      expect(subject.mountpoint).to eq '/var/lib/lxd/storage-pools/default/containers/some_guest-20200331133742'
    end

    it 'should return the container´s mountpoint in host for older snap lxd' do
      subject.created_at = '2021-04-15 13:37:23.42 UTC'.to_time

      expect(host).to receive(:exec).with("zfs list | grep guests/containers/some_guest-20210415133723").and_return [
        true,
        "guests/containers/some_guest-20210415133723    530M   725G   530M  none\n"
      ]

      subject.mountpoint
      expect(subject.mountpoint).to eq '/var/lib/lxd/storage-pools/default/containers/some_guest-20210415133723'
    end

    it 'should return the container´s mountpoint in host for snap lxd' do
      subject.created_at = '2022-03-30 09:42:42.23 UTC'.to_time

      expect(host).to receive(:exec).with("zfs list | grep guests/containers/some_guest-20220330094242").and_return [
        true,
        "guests/containers/some_guest-20220330094242    530M   725G   530M  legacy\n"
      ]

      subject.mountpoint
      expect(subject.mountpoint).to eq '/var/lib/lxd/storage-pools/default/containers/some_guest-20220330094242'
    end
  end

  describe 'lxd_info' do
    it 'should call lxc info and parse the returned yaml' do
      data = {'test' => true, 'values' => ['a', 'b']}
      expect(subject).to receive(:lxc).with("info").and_return [true, data.to_yaml]

      expect(subject.lxd_info).to eq data
    end

    it 'should underscore keys' do
      data = {testValues: {someValue: 'SomeValue'}}
      expect(subject).to receive(:lxc).with("info").and_return [true, data.to_yaml]

      expect(subject.lxd_info).to eq({'test_values' => {'some_value' => 'SomeValue'}})
    end

  end

  describe "._unroll_lxc_config_values" do
    it 'should unroll config values' do
      expect(subject.class._unroll_lxc_config_values({
        'config_a.subconfig_a' => '42',
        'config_a.subconfig_b' => 23,
        'config_b.subconfig' => 'foo',
        'config_c' => 'bar'
      })).to eq({
        "config_a"=>{
          "subconfig_a"=>"42",
          "subconfig_b"=>23
        },
        "config_b"=>{
          "subconfig"=>"foo"
        },
        "config_c"=>"bar"
      })
    end

    it 'should prefix if parent object already exisits' do
      expect(subject.class._unroll_lxc_config_values({
        'limit.cpu' => "1",
        'limit.memory' => '65536',
        'limit.memory.swap' => 'true'
      })).to eq({
        "limit" => {
          "cpu"=>"1",
          "memory"=>"65536",
          "memory.swap"=>"true"
        }
      })
    end


    it 'should prefix if child object already exisits' do
      expect(subject.class._unroll_lxc_config_values({
        'limit.cpu' => "1",
        'limit.memory.swap' => 'true',
        'limit.memory' => '65536'
      })).to eq({
        "limit" => {
          "cpu"=>"1",
          "memory"=>"65536",
          "memory.swap"=>"true"
        }
      })
    end
  end


  describe 'live_lxc_info' do
    pending
  end

  describe 'lxc_info' do
    it 'should get lxc info from host´s monitoring_last_check_result' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time

      allow(host).to receive(:monitoring_last_check_result).and_return(
        'system' => {
          'lxd' => [
            {'name' => 'some_guest-20191224234217', 'status' => 'Stopped'},
            {'name' => 'some_guest-20200331133742', 'status' => 'Running'}
          ]
        }
      )

      expect(subject.lxc_info).to eq('name' => 'some_guest-20200331133742', 'status' => 'Running')
    end
  end

  describe 'running?' do
    it 'should return true if state is running' do
      allow(subject).to receive(:live_lxc_info).and_return({'state' => {'status' => 'Running'}})
      expect(subject.running?).to eq true
    end

    it 'should return false if state is running' do
      allow(subject).to receive(:live_lxc_info).and_return({'state' => {'status' => 'Stopped'}})
      expect(subject.running?).to eq false
    end

    it 'should return true if state is running' do
      allow(subject).to receive(:live_lxc_info).and_return({})
      expect(subject.running?).to eq nil
    end
  end

  describe 'show_config' do
    it 'should parse lxc result' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      expect(subject).to receive('lxc').with('config show some_guest-20200331133742').and_return([true, {version: 42, data: true, comment: 'works'}.to_yaml])
      expect(subject.show_config).to eq({
        data: true,
        version: 42,
        comment: 'works'
      })
    end

    it 'should parse invalid lxc result' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      expect(subject).to receive('lxc').with('config show some_guest-20200331133742').and_return([true, "foo: 'bar'\n  in: 'valid'"])
      expect(subject.show_config).to eq({
        error: "YAML not parseable",
        returned: "foo: 'bar'\n  in: 'valid'"
      })
    end

    it 'should return nil if lxc fails' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      expect(subject).to receive('lxc').with('config show some_guest-20200331133742').and_return([false, ''])
      expect(subject.show_config).to eq nil
    end


    # res, ret = lxc "config show #{name}"
    # if res
    #   YAML.load ret
    # else
    #   nil
    # end
  end



  describe 'get_config' do
    it 'should get config and return it' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      expect(subject).to receive(:lxc).with('config get some_guest-20200331133742 some_key').and_return [true, "Some Return Value\n"]

      expect(subject.get_config 'some_key').to eq 'Some Return Value'
    end

    it 'should cast integer values' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      expect(subject).to receive(:lxc).with('config get some_guest-20200331133742 some_key').and_return [true, "42\n"]

      expect(subject.get_config 'some_key').to eq 42
    end

    it 'should return nil if get failed' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      expect(subject).to receive(:lxc).with('config get some_guest-20200331133742 some_key').and_return [false, "Container no found\n"]

      expect(subject.get_config 'some_key').to eq nil
    end
  end

  describe 'set_config' do
    it 'should call lxc config set' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      allow(subject).to receive(:running?).and_return true

      expect(subject).to receive(:lxc).with("config set some_guest-20200331133742 some_setting true")

      subject.set_config :some_setting, true
    end

    it 'should escape variables for shell' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      allow(subject).to receive(:running?).and_return true

      expect(subject).to receive(:lxc).with('config set some_guest-20200331133742 some\ setting something\ like\ true')

      subject.set_config 'some setting', 'something like true'
    end
  end

  describe 'unset_config' do
    it 'should call lxc config unset' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      allow(subject).to receive(:running?).and_return true

      expect(subject).to receive(:lxc).with("config unset some_guest-20200331133742 some_setting")

      subject.unset_config :some_setting
    end

    it 'should escape variables for shell' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      allow(subject).to receive(:running?).and_return true

      expect(subject).to receive(:lxc).with('config unset some_guest-20200331133742 some\ setting')

      subject.unset_config 'some setting'
    end
  end

  describe 'config_from_guest' do
    it 'should setup container according to guest' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      guest.root_fs_size = 170 * 1024

      expect(subject).to receive(:set_config).with('raw.lxc', "lxc.mount.auto = cgroup\nlxc.apparmor.profile = unconfined")
      expect(guest).to receive(:configure_lxd_container).with(subject)
      expect(subject).to receive(:lxc).with("config device set some_guest-20200331133742 root size 174080")
      expect(subject).to receive(:lxc).with("network attach lxdbr0 some_guest-20200331133742 eth0")

      subject.config_from_guest
    end

    it 'should attach guest´s custom volumes' do
      subject.created_at = '2020-03-31 13:37:42.23 UTC'.to_time
      volume = Factory.build :lxd_custom_volume, mount_point: 'floppies/cbm1541'
      allow(volume).to receive(:lxc!) # prevent from really trying to create a volume
      guest.lxd_custom_volumes << volume
      volume_extra = Factory.build :lxd_custom_volume, pool: 'dev9', mount_point: 'floppies/cbm1581'
      allow(volume_extra).to receive(:lxc!) # prevent from really trying to create a volume
      guest.lxd_custom_volumes << volume_extra

      allow(subject).to receive(:lxc)
      expect(subject).to receive(:lxc).with('storage volume attach default some_guest-floppies-cbm1541 some_guest-20200331133742 floppies/cbm1541')
      expect(subject).to receive(:lxc).with('storage volume attach dev9 some_guest-floppies-cbm1581 some_guest-20200331133742 floppies/cbm1581')

      subject.config_from_guest
    end
  end
end