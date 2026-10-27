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
    let(:sftp) { double 'sftp' }

    before do
      allow(host).to receive(:sftp).and_return(sftp)
      allow(sftp).to receive(:upload!)
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
    end

    it 'should upload public key via sftp' do
      allow_any_instance_of(CloudModel::SshKeyPair).to receive(:ensure!).and_return(true)
      expect(sftp).to receive(:upload!).with('/data/keys/id_rsa.pub', '/root/.ssh/authorized_keys')

      subject.set_authorized_keys
    end

    it 'should create the controller´s rsa key pair first when it does not exist yet' do
      expect_any_instance_of(CloudModel::SshKeyPair).to receive(:ensure!) do |pair|
        expect(pair.private_key_file).to eq '/data/keys/id_rsa'
        expect(pair.type).to eq 'rsa'
        expect(pair.bits).to eq 4096
        true
      end

      subject.set_authorized_keys
    end
  end

  describe 'deploy_zfs_sync_key' do
    let(:sftp) { double 'sftp' }

    before do
      allow(host).to receive(:sftp).and_return(sftp)
      allow(sftp).to receive(:upload!)
      allow(subject).to receive(:render_to_remote)
      allow(subject).to receive(:mkdir_p)
      allow(CloudModel::ZfsSyncKey).to receive(:ensure!).and_return(true)
      allow(CloudModel::ZfsSyncKey).to receive(:private_key_file).and_return('/data/keys/zfs_sync')
      allow(CloudModel::ZfsSyncKey).to receive(:authorized_keys_line).and_return('restrict,command="/usr/local/sbin/zfs-receive-only" ssh-ed25519 AAAA cloudmodel-zfs-sync')
    end

    it 'should make sure the key pair exists' do
      expect(CloudModel::ZfsSyncKey).to receive(:ensure!)
      subject.deploy_zfs_sync_key
    end

    it 'should upload the private key with tight permissions' do
      expect(sftp).to receive(:upload!).with('/data/keys/zfs_sync', '/root/.ssh/zfs_sync')
      expect(host).to receive(:exec!).with('chmod 600 /root/.ssh/zfs_sync', 'Failed to set mode on the ZFS sync key')
      subject.deploy_zfs_sync_key
    end

    it 'should render the forced-command wrapper executable' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/host/usr/local/sbin/zfs-receive-only', '/usr/local/sbin/zfs-receive-only', 0755)
      subject.deploy_zfs_sync_key
    end

    it 'should replace the key´s authorized_keys entry idempotently and keep other keys' do
      expect(host).to receive(:exec!).with(
        %r{\Atouch /root/.ssh/authorized_keys && grep -v cloudmodel-zfs-sync /root/.ssh/authorized_keys > /root/.ssh/authorized_keys.tmp; echo restrict,command.*zfs-receive-only.*cloudmodel-zfs-sync >> /root/.ssh/authorized_keys.tmp && mv /root/.ssh/authorized_keys.tmp /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys\z},
        'Failed to authorize the ZFS sync key'
      )
      subject.deploy_zfs_sync_key
    end

    it 'should write into the deploy root during a host deploy' do
      expect(sftp).to receive(:upload!).with('/data/keys/zfs_sync', "#{@root}/root/.ssh/zfs_sync")
      expect(subject).to receive(:render_to_remote).with('/cloud_model/host/usr/local/sbin/zfs-receive-only', "#{@root}/usr/local/sbin/zfs-receive-only", 0755)
      subject.deploy_zfs_sync_key @root
    end

    it 'should record the push on the host' do
      expect(host).to receive(:update_attribute).with(:zfs_sync_key_deployed_at, kind_of(Time))
      subject.deploy_zfs_sync_key
    end
  end

  describe 'detect_arch' do
    it 'corrects the arch field when the machine reports a different one' do
      host.update_attributes arch: 'amd64'
      allow(host).to receive(:exec!).with('uname -m', anything).and_return("aarch64\n")

      subject.detect_arch

      expect(host.reload.arch).to eq 'arm64'
    end

    it 'maps x86_64 to amd64' do
      host.update_attributes arch: 'arm64'
      allow(host).to receive(:exec!).with('uname -m', anything).and_return("x86_64\n")

      subject.detect_arch

      expect(host.reload.arch).to eq 'amd64'
    end

    it 'maps the kernel names of the recognized future arches' do
      {'ppc64le' => 'ppc64el', 'riscv64' => 'riscv64', 'loongarch64' => 'loong64'}.each do |machine, debian|
        host.update_attributes arch: 'amd64'
        allow(host).to receive(:exec!).with('uname -m', anything).and_return("#{machine}\n")
        subject.detect_arch
        expect(host.reload.arch).to eq debian
      end
    end

    it 'keeps a correct arch untouched' do
      host.update_attributes arch: 'amd64'
      allow(host).to receive(:exec!).with('uname -m', anything).and_return("x86_64\n")
      expect(host).not_to receive(:update_attributes!)

      subject.detect_arch
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

    context 'on the running host' do
      let(:client) { CloudModel::VpnClient.new name: 'dev-laptop', tinc_public_key: 'KEY', address: '10.42.253.4' }

      before do
        allow(CloudModel::VpnClient).to receive(:each).and_yield(client)
        allow(CloudModel::VpnClient).to receive(:all).and_return [client]
        allow(CloudModel::Host).to receive(:each).and_yield(host)
        allow(CloudModel::Host).to receive(:all).and_return [host]
        allow(subject).to receive(:mkdir_p)
        allow(subject).to receive(:render_to_remote)
      end

      def live_files *names
        allow(host).to receive(:exec).with('ls -1 /etc/tinc/vpn/hosts/').and_return [true, names.map { |n| "#{n}\n" }.join]
      end

      it 'writes the files of clients and hosts under their tinc node names' do
        live_files 'dev_laptop', host.name.gsub('-', '_')
        expect(subject).to receive(:render_to_remote).with('/cloud_model/host/etc/tinc/client', '/etc/tinc/vpn/hosts/dev_laptop', client: client)
        expect(subject).to receive(:render_to_remote).with('/cloud_model/host/etc/tinc/host', "/etc/tinc/vpn/hosts/#{host.name.gsub('-', '_')}", host: host)

        expect(subject.update_tinc_host_files).to eq []
      end

      it 'moves files of deleted nodes aside and reloads tincd' do
        live_files 'dev_laptop', host.name.gsub('-', '_'), 'old_vm'
        expect(host).to receive(:exec!).with('mkdir -p /etc/tinc/vpn/hosts.removed', anything)
        expect(host).to receive(:exec!).with(%r{\Amv /etc/tinc/vpn/hosts/old_vm /etc/tinc/vpn/hosts.removed/old_vm\.\d{14}\z}, anything)
        expect(host).to receive(:exec).with('systemctl reload tinc@vpn 2>/dev/null || pkill -HUP -x tincd')

        expect(subject.update_tinc_host_files).to eq ['old_vm']
      end

      it 'reloads tincd even when nothing was removed, so new client files take effect' do
        live_files 'dev_laptop', host.name.gsub('-', '_')
        expect(host).not_to receive(:exec!).with(/\Amv /, anything)
        expect(host).to receive(:exec).with('systemctl reload tinc@vpn 2>/dev/null || pkill -HUP -x tincd')

        subject.update_tinc_host_files
      end

      it 'never removes anything when the database has no nodes' do
        allow(CloudModel::VpnClient).to receive(:all).and_return []
        allow(CloudModel::Host).to receive(:all).and_return []
        live_files 'dev_laptop', 'old_vm'
        expect(host).not_to receive(:exec!).with(/\Amv /, anything)

        expect(subject.update_tinc_host_files).to eq []
      end

      it 'leaves stale files alone with prune: false' do
        live_files 'old_vm'
        expect(host).not_to receive(:exec).with('ls -1 /etc/tinc/vpn/hosts/')
        expect(host).not_to receive(:exec!).with(/\Amv /, anything)

        expect(subject.update_tinc_host_files(prune: false)).to eq []
      end
    end

    it 'does not prune or reload inside a chroot (host deploy)' do
      allow(CloudModel::VpnClient).to receive(:each)
      allow(CloudModel::Host).to receive(:each)
      allow(subject).to receive(:mkdir_p)
      expect(host).not_to receive(:exec).with('ls -1 /etc/tinc/vpn/hosts/')
      expect(host).not_to receive(:exec).with('systemctl reload tinc@vpn 2>/dev/null || pkill -HUP -x tincd')

      expect(subject.update_tinc_host_files(@root)).to eq []
    end
  end

  describe 'stale_tinc_host_files' do
    it 'lists files of nodes that are neither a VPN client nor a host' do
      allow(CloudModel::VpnClient).to receive(:all).and_return [CloudModel::VpnClient.new(name: 'a-b')]
      allow(CloudModel::Host).to receive(:all).and_return [host]
      allow(host).to receive(:exec).with('ls -1 /etc/tinc/vpn/hosts/').and_return [true, "a_b\n#{host.name.gsub('-', '_')}\ngone\n\n"]

      expect(subject.stale_tinc_host_files).to eq ['gone']
    end
  end

  describe 'tinc templates' do
    it 'fixes the path MTU in the host file instead of discovering it' do
      other = Factory :host, name: 'other', tinc_public_key: 'KEY'
      allow(other).to receive(:primary_address).and_return CloudModel::Address.from_str('192.0.2.10/24')
      allow(other).to receive(:private_network).and_return CloudModel::Address.from_str('10.42.1.0/24')
      rendered = subject.render('/cloud_model/host/etc/tinc/host', host: other)
      expect(rendered).to include "PMTU = 1414\n", "PMTUDiscovery = no\n", "ClampMSS = yes\n"
      expect(rendered).to include "Cipher = aes-256-cbc\n", "Digest = sha256\n"
      expect(rendered).not_to include 'blowfish'
    end

    it 'sets the interface MTU and queue length in tinc-up' do
      allow(host).to receive(:private_address).and_return '10.42.0.1'
      allow(host).to receive(:private_network).and_return double(tinc_subnet: 16)
      rendered = subject.render('/cloud_model/host/etc/tinc/tinc-up', host: host)
      expect(rendered).to include '/bin/ip link set $INTERFACE mtu 1400'
      expect(rendered).to include '/bin/ip link set $INTERFACE txqueuelen 2000'
    end

    it 'sizes the UDP socket buffers in tinc.conf and the kernel limits to match' do
      expect(subject.render('/cloud_model/host/etc/tinc/tinc.conf', host: host)).to include "UDPRcvBuf = 8388608\n", "UDPSndBuf = 8388608\n"
      expect(subject.render('/cloud_model/host/etc/sysctl.d/60-tinc.conf')).to include "net.core.rmem_max = 16777216\n", "net.core.wmem_max = 16777216\n"
    end
  end

  describe 'deploy_tinc_config' do
    before do
      allow(subject).to receive(:update_tinc_host_files)
      allow(subject).to receive(:render_to_remote)
      allow(subject).to receive(:config_tinc_openssl)
      allow(subject).to receive(:config_tinc_sysctl)
      allow(host).to receive(:exec!)
    end

    it 'pushes host files and tinc-up and sets MTU and queue length live without restarting tinc' do
      expect(subject).to receive(:update_tinc_host_files)
      expect(subject).to receive(:render_to_remote).with('/cloud_model/host/etc/tinc/tinc-up', '/etc/tinc/vpn/tinc-up', 0755, host: host)
      expect(host).to receive(:exec!).with('ip link set vpn mtu 1400', anything)
      expect(host).to receive(:exec!).with('ip link set vpn txqueuelen 2000', anything)
      expect(host).not_to receive(:exec!).with('systemctl restart tinc@vpn', anything)
      expect(subject).to receive(:render_to_remote).with('/cloud_model/host/etc/tinc/tinc.conf', '/etc/tinc/vpn/tinc.conf', host: host)
      expect(subject).to receive(:config_tinc_sysctl)

      subject.deploy_tinc_config
    end

    it 'restarts tinc on request' do
      expect(host).to receive(:exec!).with('systemctl restart tinc@vpn', 'Failed to restart tinc')
      subject.deploy_tinc_config restart: true
    end
  end

  describe 'config_tinc_openssl' do
    before do
      allow(subject).to receive(:render_to_remote)
      allow(subject).to receive(:mkdir_p)
    end

    it 'adds the legacy provider drop-in on OpenSSL 3' do
      allow(host).to receive(:exec).with('openssl version').and_return [true, "OpenSSL 3.0.13 30 Jan 2024\n"]
      expect(subject).to receive(:render_to_remote).with('/cloud_model/host/etc/tinc/openssl-legacy.cnf', '/etc/tinc/openssl-legacy.cnf')
      expect(subject).to receive(:render_to_remote).with('/cloud_model/host/etc/systemd/system/tinc_service_d/openssl_legacy_conf', '/etc/systemd/system/tinc@.service.d/openssl-legacy.conf')
      expect(subject.config_tinc_openssl).to eq true
    end

    it 'leaves OpenSSL 1.1 without the drop-in' do
      allow(host).to receive(:exec).with('openssl version').and_return [true, "OpenSSL 1.1.1f  31 Mar 2020\n"]
      expect(subject).not_to receive(:render_to_remote).with('/cloud_model/host/etc/systemd/system/tinc_service_d/openssl_legacy_conf', anything)
      expect(host).to receive(:exec).with('rm -f /etc/systemd/system/tinc@.service.d/openssl-legacy.conf')
      expect(subject.config_tinc_openssl).to eq false
    end

    it 'asks the OpenSSL of a new root through chroot' do
      expect(host).to receive(:exec).with('chroot /mnt/root openssl version').and_return [true, "OpenSSL 3.0.15\n"]
      expect(subject.config_tinc_openssl('/mnt/root')).to eq true
    end
  end

  describe 'config_tinc_sysctl' do
    before { allow(subject).to receive(:mkdir_p); allow(subject).to receive(:render_to_remote) }

    it 'renders the sysctl.d file and applies it on a running host' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/host/etc/sysctl.d/60-tinc.conf', '/etc/sysctl.d/60-tinc.conf')
      expect(host).to receive(:exec!).with('sysctl -q -p /etc/sysctl.d/60-tinc.conf', anything)
      subject.config_tinc_sysctl
    end

    it 'only renders into a root under construction' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/host/etc/sysctl.d/60-tinc.conf', '/mnt/root/etc/sysctl.d/60-tinc.conf')
      expect(host).not_to receive(:exec!)
      subject.config_tinc_sysctl '/mnt/root'
    end
  end

  describe 'tinc_config_changes' do
    it 'lists the files whose live content differs from the rendered one' do
      allow(CloudModel::Host).to receive(:each).and_yield(host)
      allow(subject).to receive(:render).with('/cloud_model/host/etc/tinc/tinc-up', host: host).and_return "up 1400\n"
      allow(subject).to receive(:render).with('/cloud_model/host/etc/tinc/tinc.conf', host: host).and_return "conf\n"
      allow(subject).to receive(:render).with('/cloud_model/host/etc/sysctl.d/60-tinc.conf').and_return "sys\n"
      allow(host).to receive(:exec).with('cat /etc/tinc/vpn/tinc.conf').and_return [true, "conf\n"]
      allow(host).to receive(:exec).with('cat /etc/sysctl.d/60-tinc.conf').and_return [true, "sys\n"]
      allow(subject).to receive(:render).with('/cloud_model/host/etc/tinc/host', host: host).and_return "same\n"
      allow(host).to receive(:exec).with('cat /etc/tinc/vpn/tinc-up').and_return [true, "up 1500\n"]
      allow(host).to receive(:exec).with("cat /etc/tinc/vpn/hosts/#{host.name.downcase.gsub('-', '_')}").and_return [true, "same\n"]

      expect(subject.tinc_config_changes).to eq '/etc/tinc/vpn/tinc-up' => ["up 1500\n", "up 1400\n"]
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
      # the upgrade run itself is covered in the unattended upgrades mixin spec
      expect(subject).to receive(:apply_security_updates).with(@root)
      allow(File).to receive(:exist?).and_return(true)
      sftp = double 'sftp'
      allow(host).to receive(:sftp).and_return(sftp)
      allow(sftp).to receive(:upload!)
      allow(host).to receive(:system_disks).and_return(['sda'])
      subject.instance_variable_set(:@timestamp, Time.now)
      # pushes the host-to-host sync key into the deploy root
      expect(subject).to receive(:deploy_zfs_sync_key).with(@root)

      subject.config_deploy_root
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