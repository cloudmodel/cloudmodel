require 'spec_helper'

describe CloudModel::Workers::HostWorker do
  it 'should assign host parameter' do
    host = Factory :host
    worker = CloudModel::Workers::HostWorker.new host
    expect(worker.instance_variable_get '@host').to eq host
  end

  let(:host) { Factory :host }
  subject { CloudModel::Workers::HostWorker.new host }

  before do
    allow(host).to receive(:exec)
    allow(host).to receive(:exec!)
    allow(host).to receive(:exec).with('cat /proc/mdstat').and_return [true, ""]
    allow(subject).to receive(:comment_sub_step)
    allow(subject).to receive(:chroot)
    allow(subject).to receive(:chroot!)
    @root = "/mnt/custom#{rand}/root"
    allow(subject).to receive(:root).and_return @root
  end

  describe 'root' do
    it 'should return /mnt/newroot' do
      allow(subject).to receive(:root).and_call_original
      expect(subject.root).to eq '/mnt/newroot'
    end
  end

  describe 'config_firewall' do
    it 'should create a FirewallWorker and write scripts' do
      allow(subject).to receive(:root).and_call_original
      fw = double 'firewall_worker'
      allow(CloudModel::Workers::FirewallWorker).to receive(:new).with(host).and_return(fw)
      expect(fw).to receive(:write_scripts).with(root: '/mnt/newroot')

      subject.config_firewall
    end
  end

  describe 'config_fstab' do
    it 'should render fstab to new host' do
      host.system_disks = %w(nvme11n1 sda)
      timestamp = double
      subject.instance_variable_set :@timestamp, timestamp
      expect(subject).to receive(:render_to_remote).with('/cloud_model/host/etc/fstab', "#{@root}/etc/fstab", host: host, timestamp: timestamp, swap_disks: ['nvme11n1p2', 'sda2'])

      subject.config_fstab
    end
  end

  describe 'set_authorized_keys' do
    it 'should upload public key via sftp' do
      sftp = double 'sftp'
      allow(host).to receive(:sftp).and_return(sftp)
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      expect(sftp).to receive(:upload!).with('/data/keys/id_rsa.pub', '/root/.ssh/authorized_keys')

      subject.set_authorized_keys
    end
  end

  describe 'boot_deploy_root' do
    before do
      allow(host).to receive(:mount_boot_fs).and_return true
    end

    it "should ensure boot is mounted" do
      expect(subject).to receive(:comment_sub_step).with("Ensure /boot is mounted")
      expect(host).to receive(:unmount_boot_fs).ordered
      expect(host).to receive(:mount_boot_fs).with(@root).ordered.and_return true

      subject.boot_deploy_root
    end

    it 'should copy kernel and grub to /boot' do
      expect(subject).to receive(:comment_sub_step).with("Copy kernel and grub to /boot")
      expect(subject).to receive(:chroot).with(@root, "cd /kernel; tar cf - * | ( cd /boot; tar xfp -)")

      subject.boot_deploy_root
    end

    it 'should setup grub for SATA' do
      host.system_disks = %w(sda sdb)
      expect(subject).to receive(:comment_sub_step).with('Setup grub bootloader')
      expect(subject).to receive(:chroot!).with(@root, "mdadm --detail --scan >> /etc/mdadm/mdadm.conf", "Failed to update mdadm.conf")
      expect(subject).to receive(:chroot!).with(@root, "update-initramfs -u", "Failed to update initram")
      expect(subject).to receive(:chroot!).with(@root, "grub-install --no-floppy --recheck /dev/sda", "Failed to install grub on sda")
      expect(subject).to receive(:chroot!).with(@root, "grub-mkconfig -o /boot/grub/grub.cfg", 'Failed to config grub')
      expect(subject).to receive(:chroot!).with(@root, "grub-install --no-floppy /dev/sdb", "Failed to install grub on sdb")

      subject.boot_deploy_root
    end

    it 'should setup grub for NVME and 3 disks' do
      host.system_disks = %w(nvme11n1 nvme02n1 nvme03n1)
      expect(subject).to receive(:comment_sub_step).with('Setup grub bootloader')
      expect(subject).to receive(:chroot!).with(@root, "mdadm --detail --scan >> /etc/mdadm/mdadm.conf", "Failed to update mdadm.conf").ordered
      expect(subject).to receive(:chroot!).with(@root, "update-initramfs -u", "Failed to update initram").ordered
      expect(subject).to receive(:chroot!).with(@root, "grub-install --no-floppy --recheck /dev/nvme11n1", "Failed to install grub on nvme11n1").ordered
      expect(subject).to receive(:chroot!).with(@root, "grub-mkconfig -o /boot/grub/grub.cfg", 'Failed to config grub').ordered
      expect(subject).to receive(:chroot!).with(@root, "grub-install --no-floppy /dev/nvme02n1", "Failed to install grub on nvme02n1").ordered
      expect(subject).to receive(:chroot!).with(@root, "grub-install --no-floppy /dev/nvme03n1", "Failed to install grub on nvme03n1").ordered

      subject.boot_deploy_root
    end

    it 'should reboot the host' do
      expect(subject).to receive(:comment_sub_step).with 'Reboot Host'
      expect(host).to receive(:update_attribute).ordered.with :deploy_state, :booting
      expect(host).to receive(:exec!).ordered.with 'reboot', 'Failed to reboot host'

      subject.boot_deploy_root
    end
  end

  describe 'update_tinc_host_files' do
    it 'should render tinc host files for all hosts' do
      allow(CloudModel::Host).to receive(:each)
      allow(CloudModel::VpnClient).to receive(:each)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)

      subject.update_tinc_host_files(@root)
    end
  end

  describe 'disk_partition_device' do
    let(:number_exception) { "Partition number must be a positive integer value. First partition is 1." }

    it 'should give sata/scsi partition device names' do
      expect(subject.disk_partition_device 'sda', 5).to eq "sda5"
    end

    it 'should give nvme0 partion device names' do
      expect(subject.disk_partition_device 'nvme00n1', 5).to eq "nvme00n1p5"
    end

    it 'should give (legacy) pata partition device names' do
      expect(subject.disk_partition_device 'hda', 1).to eq "hda1"
    end

    it 'should not accept non integer partition values' do
      expect{subject.disk_partition_device 'nvme00n1', '1'}.to raise_error number_exception
    end

    it 'should not accept 0 as partition number' do
      expect{subject.disk_partition_device 'sda', 0}.to raise_error number_exception
    end

    it 'should not accept negative integer as partition number' do
      expect{subject.disk_partition_device 'sda', -1}.to raise_error number_exception
    end
  end

  describe 'init_raid_device' do
    it 'should init raid on SATA' do
      host.system_disks = ['sda', 'sdb']

      expect(subject).to receive(:comment_sub_step).with("Init RAID device md0 for boot", indent: 4)

      expect(host).to receive(:exec).with(
      "mdadm --zero-superblock /dev/sda1 /dev/sdb1"
      )
      expect(host).to receive(:exec).with(
      "mdadm --create -e1 -f /dev/md0 --level=1 --raid-devices=2 /dev/sda1 /dev/sdb1"
      )
      subject.init_raid_device '', name: 'boot', device: 'md0', partition: 1
    end

    it 'should init raid on NVME' do
      host.system_disks = ['nvme11n1', 'nvme02n1']

      expect(subject).to receive(:comment_sub_step).with("Init RAID device md4 for lxd", indent: 4)

      expect(host).to receive(:exec).with(
      "mdadm --zero-superblock /dev/nvme11n1p3 /dev/nvme02n1p3"
      )
      expect(host).to receive(:exec).with(
      "mdadm --create -e1 -f /dev/md4 --level=1 --raid-devices=2 /dev/nvme11n1p3 /dev/nvme02n1p3"
      )
      subject.init_raid_device '', name: 'lxd', device: 'md4', partition: 3
    end

    it 'should init raid on more than 2 disks' do
      host.system_disks = ['nvme11n1', 'nvme02n1', 'nvme03n1']

      expect(subject).to receive(:comment_sub_step).with("Init RAID device md1 for cloud", indent: 4)

      expect(host).to receive(:exec).with(
      "mdadm --zero-superblock /dev/nvme11n1p3 /dev/nvme02n1p3 /dev/nvme03n1p3"
      )
      expect(host).to receive(:exec).with(
      "mdadm --create -e1 -f /dev/md1 --level=1 --raid-devices=3 /dev/nvme11n1p3 /dev/nvme02n1p3 /dev/nvme03n1p3"
      )
      subject.init_raid_device '', name: 'cloud', device: 'md1', partition: 3
    end

    it 'should not init already active raid' do
      host.system_disks = ['sda', 'sdb']

      expect(subject).to receive(:comment_sub_step).with("Skip RAID device md0 for boot, as already active", indent: 4)

      expect(host).not_to receive(:exec).with(
      "mdadm --zero-superblock /dev/sda1 /dev/sdb1"
      )
      expect(host).not_to receive(:exec).with(
      "mdadm --create -e1 -f /dev/md0 --level=1 --raid-devices=2 /dev/sda1 /dev/sdb1"
      )

      md_data = <<-MDSTAT
      Personalities : [raid1] [linear] [multipath] [raid0] [raid6] [raid5] [raid4] [raid10]
      md0 : active raid1 sdb1[1] sda1[0]
            261120 blocks super 1.2 [2/2] [UU]

      md1 : active raid1 sdb5[1] sda5[0]
            100596736 blocks super 1.2 [2/2] [UU]

      md4 : active raid1 sdb6[1] sda6[0]
            25148416 blocks super 1.2 [2/2] [UU]

      md3 : active raid1 sdb4[1] sda4[0]
            33520640 blocks super 1.2 [2/2] [UU]

      md2 : active raid1 sdb3[1] sda3[0]
            33520640 blocks super 1.2 [2/2] [UU]

      unused devices: <none>
      MDSTAT

      subject.init_raid_device md_data, name: 'boot', device: 'md0', partition: 1
    end
  end

  describe 'init_system_disk' do
    it 'should init partition table on all system disks' do
      host.system_disks = ['sdz', 'nvme09n2']

      expect(subject).to receive(:comment_sub_step).with("Partition system disks")

      expect(host).to receive(:exec!).with(
      "sgdisk -go " +
      "-n 1:2048:1050623 -t 1:ef02 -c 1:boot " +
      "-n 2:1050624:537921535 -t 2:8200 -c 2:swap " +
      "-n 3:537921536:605030399 -t 3:fd00 -c 3:root_a " +
      "-n 4:605030400:672139263 -t 4:fd00 -c 4:root_b " +
      "-n 5:672139264:873465855 -t 5:fd00 -c 5:cloud " +
      "-n 6:873465856:923797503 -t 6:fd00 -c 6:lxd " +
      "-N 7 -t 7:8300 -c 7:guests /dev/sdz",
      "Failed to create partitions on sdz"
      )
      expect(host).to receive(:exec!).with(
      "sgdisk -go " +
      "-n 1:2048:1050623 -t 1:ef02 -c 1:boot " +
      "-n 2:1050624:537921535 -t 2:8200 -c 2:swap " +
      "-n 3:537921536:605030399 -t 3:fd00 -c 3:root_a " +
      "-n 4:605030400:672139263 -t 4:fd00 -c 4:root_b " +
      "-n 5:672139264:873465855 -t 5:fd00 -c 5:cloud " +
      "-n 6:873465856:923797503 -t 6:fd00 -c 6:lxd " +
      "-N 7 -t 7:8300 -c 7:guests /dev/nvme09n2",
      "Failed to create partitions on nvme09n2"
      )
      subject.init_system_disk
    end

    it 'should init swap on all system disks' do
      host.system_disks = ['sdz', 'nvme09n2']

      expect(subject).to receive(:comment_sub_step).with("Make swap space")

      expect(host).to receive(:exec!).with(
      "mkswap /dev/sdz2",
      "Failed to create swap on sdz"
      )
      expect(host).to receive(:exec!).with(
      "mkswap /dev/nvme09n2p2",
      "Failed to create swap on nvme09n2"
      )
      subject.init_system_disk
    end

    it 'should init md0 (boot) with all system disks' do
      host.system_disks = ['sdz', 'nvme09n2']
      md_data = "Personalities : [raid1] [linear] [multipath] [raid0] [raid6] [raid5] [raid4] [raid10]\n#{rand}"

      allow(host).to receive(:exec).with('cat /proc/mdstat').and_return [true, md_data]
      allow(subject).to receive(:init_raid_device)
      expect(subject).to receive(:init_raid_device).with(md_data, name: 'boot', device: 'md0', partition: 1)

      subject.init_system_disk
    end

    it 'should init md1 (cloud) with all system disks' do
      host.system_disks = ['sdz', 'nvme09n2']
      md_data = "Personalities : [raid1] [linear] [multipath] [raid0] [raid6] [raid5] [raid4] [raid10]\n#{rand}"

      allow(host).to receive(:exec).with('cat /proc/mdstat').and_return [true, md_data]
      allow(subject).to receive(:init_raid_device)
      expect(subject).to receive(:init_raid_device).with(md_data, name: 'cloud', device: 'md1', partition: 5)

      subject.init_system_disk
    end

    it 'should init md2 (root_a) with all system disks' do
      host.system_disks = ['sdz', 'nvme09n2']
      md_data = "Personalities : [raid1] [linear] [multipath] [raid0] [raid6] [raid5] [raid4] [raid10]\n#{rand}"

      allow(host).to receive(:exec).with('cat /proc/mdstat').and_return [true, md_data]
      allow(subject).to receive(:init_raid_device)
      expect(subject).to receive(:init_raid_device).with(md_data, name: 'root_a', device: 'md2', partition: 3)

      subject.init_system_disk
    end

    it 'should init md3 (root_b) with all system disks' do
      host.system_disks = ['sdz', 'nvme09n2']
      md_data = "Personalities : [raid1] [linear] [multipath] [raid0] [raid6] [raid5] [raid4] [raid10]\n#{rand}"

      allow(host).to receive(:exec).with('cat /proc/mdstat').and_return [true, md_data]
      allow(subject).to receive(:init_raid_device)
      expect(subject).to receive(:init_raid_device).with(md_data, name: 'root_b', device: 'md3', partition: 4)

      subject.init_system_disk
    end

    it 'should init md4 (lxd) with all system disks' do
      host.system_disks = ['sdz', 'nvme09n2']
      md_data = "Personalities : [raid1] [linear] [multipath] [raid0] [raid6] [raid5] [raid4] [raid10]\n#{rand}"

      allow(host).to receive(:exec).with('cat /proc/mdstat').and_return [true, md_data]
      allow(subject).to receive(:init_raid_device)
      expect(subject).to receive(:init_raid_device).with(md_data, name: 'lxd', device: 'md4', partition: 6)

      subject.init_system_disk
    end

    it 'should format boot array with EXT2' do
      expect(subject).to receive(:comment_sub_step).with("Format boot array")

      expect(host).to receive(:exec!).with('mkfs.ext2 /dev/md0', 'Failed to create boot filesystem')

      subject.init_system_disk
    end

    it 'should format with EXT4 and mount cloud array' do
      expect(subject).to receive(:comment_sub_step).with("Format cloud array")
      expect(host).to receive(:exec!).with('mkfs.ext4 /dev/md1', 'Failed to create cloud filesystem').ordered
      expect(host).to receive(:exec).with('mkdir -p /cloud')
      expect(host).to receive(:exec!).with('mount /dev/md1 /cloud', 'Failed to mount cloud filesystem')

      subject.init_system_disk
    end

    it 'should format with EXT4 and mount lxd array' do
      expect(subject).to receive(:comment_sub_step).with("Format cloud array")
      expect(host).to receive(:exec!).with('mkfs.ext4 /dev/md4', 'Failed to create lxd filesystem').ordered
      expect(host).to receive(:exec).with('mkdir -p /var/lib/lxd')
      expect(host).to receive(:exec!).with('mount /dev/md4 /var/lib/lxd', 'Failed to mount lxd filesystem')

      subject.init_system_disk
    end
  end

  describe 'ensure_cloud_filesystem' do
    it 'should mount /cloud if not mounted' do
      allow(host).to receive(:mounted_at?).with('/cloud').and_return(false)
      allow(subject).to receive(:mkdir_p).with('/cloud')
      expect(host).to receive(:exec!).with('mount /dev/md1 /cloud', 'Failed to mount cloud filesystem')

      subject.ensure_cloud_filesystem
    end

    it 'should skip if already mounted' do
      allow(host).to receive(:mounted_at?).with('/cloud').and_return(true)
      expect(host).not_to receive(:exec!).with('mount /dev/md1 /cloud', anything)

      subject.ensure_cloud_filesystem
    end
  end

  describe 'deploy_root_device' do
    it 'should return /dev/md2 when current root is not /dev/md2' do
      allow(host).to receive(:exec).with('findmnt -n -o SOURCE /').and_return([true, '/dev/md3'])

      expect(subject.deploy_root_device).to eq '/dev/md2'
    end

    it 'should return /dev/md3 when current root is /dev/md2' do
      allow(host).to receive(:exec).with('findmnt -n -o SOURCE /').and_return([true, '/dev/md2'])

      expect(subject.deploy_root_device).to eq '/dev/md3'
    end
  end

  describe 'make_deploy_root' do
    it 'should create and mount filesystem' do
      allow(subject).to receive(:deploy_root_device).and_return('/dev/md2')
      allow(subject).to receive(:mkdir_p)

      subject.make_deploy_root
    end
  end

  describe 'use_last_deploy_root' do
    it 'should mount deploy root if not mounted' do
      allow(host).to receive(:mounted_at?).with(@root).and_return(false)
      allow(subject).to receive(:deploy_root_device).and_return('/dev/md2')
      allow(subject).to receive(:mkdir_p)

      subject.use_last_deploy_root
    end
  end

  describe 'populate_deploy_root' do
    it 'should upload template and unpack' do
      allow(subject).to receive(:ensure_cloud_filesystem)
      template = double 'template', tarball: '/inst/template.tar'
      allow(CloudModel::HostTemplate).to receive(:last_useable).and_return(template)
      allow(subject).to receive(:upload_template)
      allow(subject).to receive(:current_indent).and_return(2)
      allow(subject).to receive(:current_counter_prefix).and_return('1.')
      allow(subject).to receive(:mkdir_p)

      subject.populate_deploy_root
    end
  end

  describe 'render_guest_zpool_service' do
    it 'should render zpool init script to be started at first boot' do
      host.system_disks = ['sda', 'sdb']

      expect(subject).to receive(:render_to_remote).with "/cloud_model/host/etc/systemd/system/guest_zpool.service", "#{@root}/etc/systemd/system/guest_zpool.service", guests_init_string: "mirror sda7 sdb7", host: host
      expect(subject).to receive(:mkdir_p).with "#{@root}/etc/systemd/system/basic.target.wants"
      expect(subject).to receive(:chroot!).with @root, "ln -s /etc/systemd/system/guest_zpool.service /etc/systemd/system/basic.target.wants/guest_zpool.service", "Failed to add guest_zpool to autostart"

      subject.render_guest_zpool_service
    end

    it 'should render extra zpools' do
      host.system_disks = ['nvme11n1', 'nvme02n1']
      host.extra_zpools.new name: 'data', init_string: "mirror sda sdb"

      expect(subject).to receive(:render_to_remote).with "/cloud_model/host/etc/systemd/system/guest_zpool.service", "#{@root}/etc/systemd/system/guest_zpool.service", guests_init_string: "mirror nvme11n1p7 nvme02n1p7", host: host
      expect(subject).to receive(:mkdir_p).with "#{@root}/etc/systemd/system/basic.target.wants"
      expect(subject).to receive(:chroot!).with @root, "ln -s /etc/systemd/system/guest_zpool.service /etc/systemd/system/basic.target.wants/guest_zpool.service", "Failed to add guest_zpool to autostart"

      subject.render_guest_zpool_service
    end
  end

  describe 'config_deploy_root' do
    it 'should render config files to deploy root' do
      allow(subject).to receive(:render_to_remote)
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:update_tinc_host_files)
      allow(subject).to receive(:render_guest_zpool_service)
      allow(subject).to receive(:config_firewall)
      allow(subject).to receive(:config_fstab)
      allow(subject).to receive(:local_exec)
      allow(File).to receive(:exist?).and_return(true)
      sftp = double 'sftp'
      allow(host).to receive(:sftp).and_return(sftp)
      allow(sftp).to receive(:upload!)
      allow(host).to receive(:system_disks).and_return(['sda'])
      subject.instance_variable_set(:@timestamp, Time.now)

      subject.config_deploy_root
    end
  end

  describe 'config_lxd' do
    it 'should init lxd and create network bridge' do
      allow(host).to receive(:private_address).and_return('10.42.0.1')
      allow(host).to receive(:private_network).and_return(double(subnet: 24))

      subject.config_lxd
    end
  end

  describe 'recover_lxd' do
    it 'should be defined' do
      expect(subject).to respond_to(:recover_lxd)
    end
  end

  describe 'update_tinc' do
    it 'should call Host.update_tinc_keys' do
      allow(CloudModel::Host).to receive(:update_tinc_keys)

      subject.update_tinc
    end
  end

  describe 'make_keys' do
    it 'should create tinc key directory and render key' do
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)

      subject.make_keys
    end
  end

  describe 'copy_keys' do
    it 'should copy tinc and ssh keys from old root' do
      allow(subject).to receive(:mkdir_p)

      subject.copy_keys
    end
  end

  describe 'sync_inst_images' do
    it 'should sync images via host' do
      allow(CloudModel.config).to receive(:skip_sync_images).and_return(false)
      allow(host).to receive(:sync_inst_images)

      subject.sync_inst_images
    end

    it 'should raise when skip_sync_images is set' do
      allow(CloudModel.config).to receive(:skip_sync_images).and_return(true)

      expect { subject.sync_inst_images }.to raise_error('skipped')
    end
  end

  describe 'deploy' do
    it 'should return false if not pending' do
      allow(host).to receive(:deploy_state).and_return(:finished)
      expect(subject.deploy).to eq false
    end

    it 'should run deploy steps when pending' do
      allow(host).to receive(:deploy_state).and_return(:pending)
      allow(host).to receive(:update_attributes)
      allow(subject).to receive(:run_steps)

      expect { subject.deploy }.to output(/Finished/).to_stdout
    end
  end

  describe 'redeploy' do
    it 'should return false if not pending' do
      allow(host).to receive(:deploy_state).and_return(:finished)
      expect(subject.redeploy).to eq false
    end

    it 'should run redeploy steps when pending' do
      allow(host).to receive(:deploy_state).and_return(:pending)
      allow(host).to receive(:update_attributes)
      allow(subject).to receive(:run_steps)

      expect { subject.redeploy }.to output(/Finished/).to_stdout
    end
  end

end