require 'fileutils'
require 'net/http'
require 'net/sftp'
require 'securerandom'

module CloudModel
  module Workers
    class HostWorker < BaseWorker

      def host
        @host
      end

      def root
        "/mnt/newroot"
      end

      def config_firewall
        #
        # Configure firewall
        #

        CloudModel::Workers::FirewallWorker.new(@host).write_scripts root: root
      end

      def config_fstab
        #
        # Configure fstab
        #

        render_to_remote '/cloud_model/host/etc/fstab', "#{root}/etc/fstab", host: @host, timestamp: @timestamp, swap_disks: @host.system_disks.map{|d| disk_partition_device d, 2}
      end

      def set_authorized_keys options={}
        prepare_chroot root
        @host.sftp.upload! "#{CloudModel.config.data_directory}/keys/id_rsa.pub", "/root/.ssh/authorized_keys"
        # TODO: Add mode where no initial_root_pw is given, but external ip is used
        # @host.update_attribute :initial_root_pw, nil
      end

      def boot_deploy_root options={}
        comment_sub_step 'Ensure /boot is mounted'
        @host.unmount_boot_fs

        unless @host.mount_boot_fs root
          raise "Failed to mount /boot to chroot"
        end

        comment_sub_step 'Copy kernel and grub to /boot'
        chroot root, "cd /kernel; tar cf - * | ( cd /boot; tar xfp -)"

        # #
        # # chroot to execute grub bootstrap script
        # #
        # success, mtab = @host.exec('mount')
        # print '.'

        #render_to_remote "/cloud_model/host/etc/default/grub", "#{root}/etc/default/grub", root: @deploy_lv

        comment_sub_step 'Setup grub bootloader'
        chroot! root, "mdadm --detail --scan >> /etc/mdadm/mdadm.conf", "Failed to update mdadm.conf"
        chroot! root, "update-initramfs -u", "Failed to update initram"
        chroot! root, "grub-install --no-floppy --recheck /dev/#{@host.system_disks.first}", "Failed to install grub on #{@host.system_disks.first}"
        chroot! root, "grub-mkconfig -o /boot/grub/grub.cfg", 'Failed to config grub'
        @host.system_disks[1..].each do |dev|
          chroot! root, "grub-install --no-floppy /dev/#{dev}", "Failed to install grub on #{dev}"
        end

        unless options[:no_reboot]
          comment_sub_step 'Reboot Host'
          @host.update_attribute :deploy_state, :booting

          #
          # Reboot host
          #

          @host.exec! 'reboot', 'Failed to reboot host'
        end
      end

      def update_tinc_host_files root = ''
        #
        # Update tinc host files
        #

        mkdir_p "#{root}/etc/tinc/vpn/hosts/"
        CloudModel::VpnClient.each do |client|
          render_to_remote "/cloud_model/host/etc/tinc/client", "#{root}/etc/tinc/vpn/hosts/#{client.name.downcase.gsub('-', '_').shellescape}", client: client
        end

        CloudModel::Host.each do |host|
          render_to_remote "/cloud_model/host/etc/tinc/host", "#{root}/etc/tinc/vpn/hosts/#{host.name.downcase.gsub('-', '_').shellescape}", host: host
        end

        true
      end

      def disk_partition_device device, number
        if not number.is_a? Integer or number < 1
          raise "Partition number must be a positive integer value. First partition is 1."
        end

        if device =~ /\A[sh]d/
          "#{device}#{number}"
        else
          "#{device}p#{number}"
        end
      end

      def init_raid_device md_data, md
        if md_data =~ /#{md[:device]} \: active raid1/
          comment_sub_step "Skip RAID device #{md[:device]} for #{md[:name]}, as already active", indent: 4
        else
          comment_sub_step "Init RAID device #{md[:device]} for #{md[:name]}", indent: 4
          devs = @host.system_disks.map{|dev| "/dev/#{disk_partition_device dev, md[:partition]}"}
          @host.exec "mdadm --zero-superblock #{devs * ' '}"
          @host.exec "mdadm --create -e1 -f /dev/#{md[:device]} --level=1 --raid-devices=#{devs.size} #{devs * ' '}"
        end
      end

      def init_system_disk
        comment_sub_step 'Partition system disks'

        part_cmd = "sgdisk -go " +
          "-n 1:2048:526335 -t 1:ef02 -c 1:boot " +
          "-n 2:526336:67635199 -t 2:8200 -c 2:swap " +
          "-n 3:67635200:134744063 -t 3:fd00 -c 3:root_a " +
          "-n 4:134744064:201852927 -t 4:fd00 -c 4:root_b " +
          "-n 5:201852928:403179519 -t 5:fd00 -c 5:cloud " +
          "-n 6:403179520:453511168 -t 6:fd00 -c 6:lxd " +
          "-N 7 -t 7:8300 -c 7:guests "

        @host.system_disks.each do |dev|
          @host.exec! part_cmd + "/dev/#{dev}", "Failed to create partitions on #{dev}"
        end

        comment_sub_step 'Make RAID'

        if md_data = @host.exec('cat /proc/mdstat') and md_data[0] and md_data = md_data[1]
          init_raid_device md_data, name: 'boot', device: 'md0', partition: 1
          init_raid_device md_data, name: 'cloud', device: 'md1', partition: 5
          init_raid_device md_data, name: 'root_a', device: 'md2', partition: 3
          init_raid_device md_data, name: 'root_b', device: 'md3', partition: 4
          init_raid_device md_data, name: 'lxd', device: 'md4', partition: 6
        else
          raise 'Failed to stat md data'
        end

        comment_sub_step 'Make swap space'

        @host.system_disks.each do |dev|
          @host.exec! "mkswap /dev/#{disk_partition_device dev, 2}", "Failed to create swap on #{dev}"
        end

        comment_sub_step 'Format boot array'

        @host.exec! 'mkfs.ext2 /dev/md0', 'Failed to create boot filesystem'

        comment_sub_step 'Format cloud array'

        @host.exec! 'mkfs.ext4 /dev/md1', 'Failed to create cloud filesystem'
        @host.exec 'mkdir -p /cloud'
        @host.exec! 'mount /dev/md1 /cloud', 'Failed to mount cloud filesystem'

        comment_sub_step 'Format lxd array'

        @host.exec! 'mkfs.ext4 /dev/md4', 'Failed to create lxd filesystem'
        @host.exec 'mkdir -p /var/lib/lxd'
        @host.exec! 'mount /dev/md4 /var/lib/lxd', 'Failed to mount lxd filesystem'
      end

      def ensure_cloud_filesystem
        unless @host.mounted_at? '/cloud'
          mkdir_p "/cloud"
          @host.exec! 'mount /dev/md1 /cloud', 'Failed to mount cloud filesystem'
        end
      end

      def deploy_root_device
        if @deploy_root_device
          #debug "DRD cached"
          return @deploy_root_device
        else
          current_root_device = @host.exec('findmnt -n -o SOURCE /')[1].strip
          @deploy_root_device = "/dev/md2"

          if current_root_device == '/dev/md2'
            @deploy_root_device = "/dev/md3"
          end

          @deploy_root_device
        end
      end

      def make_deploy_root
        @host.exec "umount #{deploy_root_device}"
        @host.exec "umount #{root}"
        mkdir_p root

        @host.exec! "mkfs.ext4 #{deploy_root_device}", "Failed to create system fs"
        @host.exec! "mount #{deploy_root_device} #{root}", "Failed to mount system fs"
        mkdir_p "#{root}/var/lib/lxd"
        @host.exec! "mount /dev/md4 #{root}/var/lib/lxd", "Failed to mount system fs"
      end

      def use_last_deploy_root
        unless @host.mounted_at? root
          mkdir_p root
          @host.exec "umount #{deploy_root_device}"
          @host.exec! "mount #{deploy_root_device} #{root}", "Failed to mount system fs"
        end
      end

      def populate_deploy_root
        ensure_cloud_filesystem

        # make sure there is a HostTemplate and find out its tar file
        template = CloudModel::HostTemplate.last_useable(@host,
          indent: current_indent + 2,
          counter_prefix: "#{current_counter_prefix}",
          prepend_output: " [Building]\n"
        )

        # TODO: only do this if needed
        upload_template template

        #
        # Populate deploy root with system image
        #
        @host.exec! "cd #{root} && tar xzpf #{template.tarball}", "Failed to unpack system image!"

        mkdir_p "#{root}/inst"
      end

      def render_guest_zpool_service
        # Init zfspool on first boot if needed
        #comment_sub_step 'render guest_zpool service'
        render_to_remote "/cloud_model/host/etc/systemd/system/guest_zpool.service", "#{root}/etc/systemd/system/guest_zpool.service", zpools:
          @host.extra_zpools.as_hash.merge(default: "mirror #{@host.system_disks.map{|d| disk_partition_device d, 7} * ' '}")
        mkdir_p "#{root}/etc/systemd/system/basic.target.wants"
        chroot! root, "ln -s /etc/systemd/system/guest_zpool.service /etc/systemd/system/basic.target.wants/guest_zpool.service", "Failed to add guest_zpool to autostart"
      end

      def config_deploy_root
        #mkdir_p "#{root}/etc/conf.d"

        comment_sub_step 'render network config'

        render_to_remote "/cloud_model/host/etc/systemd/system/network.service", "#{root}/etc/systemd/system/network.service", host: @host
        chroot root, "ln -sf /etc/systemd/system/network.service /etc/systemd/system/multi-user.target.wants/"
        render_to_remote "/cloud_model/support/etc/systemd/resolved.conf", "#{root}/etc/systemd/resolved.conf", host: @host
        #chroot! root, "systemd-resolve -i eth0#{CloudModel.config.dns_servers.each{|dns_server| " --set-dns #{dns_server}"}} ", "Failed to set DNS Servers"

        comment_sub_step 'config hostname and machine info'

        render_to_remote "/cloud_model/support/etc/hostname", "#{root}/etc/hostname", host: @host
        render_to_remote "/cloud_model/support/etc/machine_info", "#{root}/etc/machine-info", host: @host

        comment_sub_step 'config firewall'

        config_firewall

        comment_sub_step 'config lxd bridge network'

        render_to_remote "/cloud_model/host/etc/default/lxd-bridge", "#{root}/etc/default/lxd-bridge", host: @host

        comment_sub_step 'config tinc vpn hosts'

        # TINC part
        mkdir_p "#{root}/etc/tinc/vpn"
        update_tinc_host_files root

        comment_sub_step 'render tinc config'

        render_to_remote "/cloud_model/host/etc/tinc/tinc.conf", "#{root}/etc/tinc/vpn/tinc.conf", host: @host
        render_to_remote "/cloud_model/host/etc/tinc/tinc-up", "#{root}/etc/tinc/vpn/tinc-up", 0755, host: @host


        comment_sub_step 'render fstab'
        config_fstab

        comment_sub_step 'config open files'
        render_to_remote "/cloud_model/host/etc/sysctl.conf", "#{root}/etc/sysctl.conf", host: @host
        render_to_remote "/cloud_model/host/etc/security/limits.conf", "#{root}/etc/security/limits.conf", host: @host

        comment_sub_step 'config ssh keys'
        # Config /root/.ssh/authorized_keys
        unless File.exists?("#{CloudModel.config.data_directory}/keys/id_rsa")
          # Create key pair if non exists
          local_exec "mkdir -p #{CloudModel.config.data_directory.shellescape}/keys"
          local_exec "ssh-keygen -N '' -t rsa -b 4096 -f #{CloudModel.config.data_directory.shellescape}/keys/id_rsa"
        end
        ssh_dir = "#{root}/root/.ssh"
        mkdir_p ssh_dir

        @host.sftp.upload! "#{CloudModel.config.data_directory}/keys/id_rsa.pub", "#{ssh_dir}/authorized_keys"

        render_to_remote "/cloud_model/host/etc/ssh/sshd_config", "#{root}/etc/ssh/sshd_config", host: @host

        comment_sub_step 'config exim mailer'

        # Config exim form mail out
        render_to_remote "/cloud_model/host/etc/exim/exim-out.conf", "#{root}/etc/exim4/exim4.conf", host: @host

        comment_sub_step 'config lm_sensors'

        chroot root, "/usr/sbin/sensors-detect --auto"

        return true
      end

      def config_lxd
        chroot root, "/usr/bin/lxd init --auto --storage-backend zfs --storage-pool guests"
        # lxc profile device add default root disk path=/ pool=guests
        # lxc storage set default volume.zfs.use_refquota true
        chroot root, "/usr/bin/lxc network create lxdbr0 ipv6.address=none ipv4.address=#{host.private_address}/#{host.private_network.subnet} ipv4.nat=true"
      end

      def recover_lxd
        # # lxd recover
       #  This LXD server currently has the following storage pools:
       #  Would you like to recover another storage pool? (yes/no) [default=no]: yes
       #  Name of the storage pool: default
       #  Name of the storage backend (dir, zfs): zfs
       #  Source of the storage pool (block device, volume group, dataset, path, ... as applicable): guests
       #  Additional storage pool configuration property (KEY=VALUE, empty when done): zfs.pool_name=guests
       #  Additional storage pool configuration property (KEY=VALUE, empty when done):
       #  Would you like to recover another storage pool? (yes/no) [default=no]:
      end

      def update_tinc
        begin
          CloudModel::Host.update_tinc_keys
        rescue
        end
      end

      def make_keys
        mkdir_p "#{root}/etc/tinc/vpn/"
        render_to_remote "/cloud_model/host/etc/tinc/rsa_key.priv", "#{root}/etc/tinc/vpn/rsa_key.priv", 0600, host: @host
        # Host SSH keys will not be generated on first host start on Ubuntu
        chroot root, "dpkg-reconfigure openssh-server"
      end

      def copy_keys
        # TODO: put keys to a more failsafe location like somewhere in /inst

        begin
          mkdir_p "#{root}/etc/tinc/vpn/"
          @host.exec! "cp -ra /etc/tinc/vpn/rsa_key.priv #{root}/etc/tinc/vpn/rsa_key.priv", "Failed to copy old tinc key"
        rescue
          print " (old tinc key not found, create new)"
          make_keys
        end

        begin
          @host.exec! "cp -ra /etc/ssh/ssh_host_*key* #{root}/etc/ssh/", "Failed to copy old ssh keys"
        rescue
          print " (old ssh keys not found)"
        end
      end

      def sync_inst_images
        if CloudModel.config.skip_sync_images
          raise 'skipped'
        end

        @host.sync_inst_images
      end

      def deploy options={}
        return false unless @host.deploy_state == :pending or options[:force]

        @host.update_attributes deploy_state: :running, deploy_last_issue: nil

        build_start_at = Time.now

        steps = [
          ['Allow to access with SSH key', :set_authorized_keys],
          ['Prepare disk for new system', :init_system_disk],
          ['Upsync system images', :sync_inst_images],
          ['Prepare volume for new system', :make_deploy_root, on_skip: :use_last_deploy_root],
          ['Populate volume with new system image', :populate_deploy_root],
          ['Make crypto keys', :make_keys],
          ['Config new system', :config_deploy_root],
          ['Render guest_zpool.service', :render_guest_zpool_service],
          # TODO: apply existing guests and restore backups
          ['Config LXD', :config_lxd],
          ['Update TINC config', :update_tinc],
          ['Write boot config and reboot', :boot_deploy_root],
        ]

        run_steps :deploy, steps, options

        @host.update_attributes deploy_state: :finished, last_deploy_finished_at: Time.now

        puts "Finished deploy host in #{distance_of_time_in_words_to_now build_start_at}"
      end

      def redeploy options={}
        return false unless @host.deploy_state == :pending or options[:force]

        @host.update_attributes deploy_state: :running, deploy_last_issue: nil

        build_start_at = Time.now

        steps = [
          ['Upsync system images', :sync_inst_images],
          ['Prepare volume for new system', :make_deploy_root, on_skip: :use_last_deploy_root],
          ['Populate volume with new system image', :populate_deploy_root],
          ['Config new system', :config_deploy_root],
          ['Copy crypto keys from old system', :copy_keys],
          ['Write boot config and reboot', :boot_deploy_root],
        ]

        run_steps :deploy, steps, options

        @host.update_attributes deploy_state: :finished, last_deploy_finished_at: Time.now

        puts "Finished redeploy host in #{distance_of_time_in_words_to_now build_start_at}"
      end

    end
  end
end