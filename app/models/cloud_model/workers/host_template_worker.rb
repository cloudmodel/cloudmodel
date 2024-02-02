module CloudModel
  module Workers
    class HostTemplateWorker < TemplateWorker
      def build_path
        if @options[:build_path]
           @options[:build_path]
         else
           "/cloud/build/host/#{@template.id}/"
         end
      end

      def error_log_object
        @template
      end

      def install_utils
        comment_sub_step 'Install console-setup'
        chroot! build_path, "apt-get install console-setup -y", "Failed to install console-setup"
        comment_sub_step 'Install mdadm'
        chroot! build_path, "apt-get install mdadm -y", "Failed to install mdadm"
        # comment_sub_step 'Install btrfs'
        # chroot! build_path, "apt-get install sudo btrfs-tools -y", "Failed to install btrfs"
        comment_sub_step 'Install zfs'
        #chroot! build_path, "apt-get install zfs-dkms -y", "Failed to install zfs"
        chroot! build_path, "apt-get install zfs-initramfs -y", "Failed to install zfs"
        # Init zfspool on first boot if needed
        render_to_remote "/cloud_model/host/etc/systemd/system/guest_zpool.service", "#{build_path}/etc/systemd/system/guest_zpool.service"
        mkdir_p "#{build_path}/etc/systemd/system/basic.target.wants"
        chroot! build_path, "ln -s /etc/systemd/system/guest_zpool.service /etc/systemd/system/basic.target.wants/guest_zpool.service", "Failed to add guest_zpool to autostart"
        comment_sub_step 'Install curl and nano'
        chroot! build_path, "apt-get install sudo curl nano -y", "Failed to install curl and nano"
        comment_sub_step 'Install debootstrap'
        chroot! build_path, "apt-get install sudo debootstrap -y", "Failed to install debootstrap"
      end

      def install_network
        comment_sub_step 'Install netbase'
        chroot! build_path, "apt-get install netbase iproute2 iptables -y", "Failed to install network base"
        comment_sub_step 'Install bridge-utils'
        chroot! build_path, "apt-get install bridge-utils -y", "Failed to install bridge-utils"

        comment_sub_step 'Setup Firewall service'
        render_to_remote "/cloud_model/host/etc/systemd/system/firewall.service", "#{build_path}/etc/systemd/system/firewall.service"
        mkdir_p "#{build_path}/etc/systemd/system/basic.target.wants"
        chroot! build_path, "ln -s /etc/systemd/system/firewall.service /etc/systemd/system/basic.target.wants/firewall.service", "Failed to add firewall to autostart"
      end

      def install_tinc
        chroot! build_path, "apt-get install tinc -y", "Failed to install tinc"
        #mkdir_p "#{build_path}/etc/systemd/system/basic.target.wants"
        mkdir_p "#{build_path}/etc/systemd/system/tinc.service.wants"
        chroot! build_path, "ln -s /lib/systemd/system/tinc@.service /etc/systemd/system/tinc.service.wants/tinc@vpn.service", "Failed to add tinc to autostart"
        #chroot! build_path, "echo vpn >> /etc/tinc/nets.boot", "Failed to add vpn to boot networks of tinc"
      end

      def install_lxd
        chroot! build_path, "apt-get install lxd -y", "Failed to install LXD"

        mkdir_p "/etc/systemd/system/multi-user.target.wants"
        mkdir_p "/etc/systemd/system/sockets.target.wants"
        #chroot! build_path, "ln -s /lib/systemd/system/lxd-containers.service /etc/systemd/system/multi-user.target.wants/lxd-containers.service", "Failed to add lxd containers to autostart"
        #chroot! build_path, "ln -s /lib/systemd/system/lxd-agent.service /etc/systemd/system/multi-user.target.wants/lxd-agent.service", "Failed to add lxd agent to autostart"
        #chroot! build_path, "ln -s /lib/systemd/system/lxd.socket /etc/systemd/system/sockets.target.wants/lxd.socket", "Failed to add lxd socket to autostart"

        render_to_remote "/cloud_model/host/etc/systemd/system/lxcfs.service", "#{build_path}/etc/systemd/system/lxcfs.service"

        #comment_sub_step 'Create guests directory'
        #mkdir_p "#{build_path}/cloud/guests"
      end

      def install_exim
        chroot! build_path, "apt-get install exim4 -y", "Failed to install Exim"

        mkdir_p "#{build_path}/etc/systemd/system/basic.target.wants"
        chroot! build_path, "ln -s /lib/systemd/system/exim4.service /etc/systemd/system/basic.target.wants/exim4.service", "Failed to add exim to autostart"
      end

      def install_check_mk_agent
        chroot! build_path, "apt-get install lm-sensors smartmontools -y", "Failed to install CheckMKAgent dependencies"

        chroot! build_path, "curl -s https://raw.githubusercontent.com/Checkmk/checkmk/2.2.0/agents/check_mk_agent.linux >/usr/bin/check_mk_agent && chmod 755 /usr/bin/check_mk_agent", "Failed to install CheckMKAgent"

        mkdir_p "#{build_path}/usr/lib/check_mk_agent/plugins/"
        %w(cgroup_cpu zfs lxd sensors smart systemd).each do |plugin|
          render_to_remote "/cloud_model/support/usr/lib/check_mk_agent/plugins/#{plugin}", "#{build_path}/usr/lib/check_mk_agent/plugins/#{plugin}", 0755
        end

        render_to_remote "/cloud_model/guest/etc/systemd/system/check_mk@.service", "#{build_path}/etc/systemd/system/check_mk@.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/check_mk.socket", "#{build_path}/etc/systemd/system/check_mk.socket"
        mkdir_p "#{build_path}/etc/systemd/system/sockets.target.wants"
        chroot! build_path, "ln -s /etc/systemd/system/check_mk.socket /etc/systemd/system/sockets.target.wants/check_mk.socket", "Failed to add check_mk to autostart"

        render_to_remote "/cloud_model/support/usr/sbin/cgroup_load_writer", "#{build_path}/usr/sbin/cgroup_load_writer", 0755
        render_to_remote "/cloud_model/guest/etc/systemd/system/cgroup_load_writer.service", "#{build_path}/etc/systemd/system/cgroup_load_writer.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/cgroup_load_writer.timer", "#{build_path}/etc/systemd/system/cgroup_load_writer.timer"
        chroot! build_path, "ln -s /etc/systemd/system/cgroup_load_writer.timer /etc/systemd/system/timers.target.wants/cgroup_load_writer.timer", "Failed to enable cgroup_load_writer service"
      end

      def install_kernel
        #chroot! build_path, "apt-get install --install-recommends linux-image-#{ubuntu_kernel_flavour} -y", "Failed to install linux kernel"
        chroot! build_path, "apt-get install --install-recommends linux-image-#{ubuntu_arch} -y", "Failed to install linux kernel"
      end

      def install_grub
        chroot! build_path, "apt-get install grub2 -y", "Failed to install Grub"
        render_to_remote "/cloud_model/host/etc/default/grub", "#{build_path}/etc/default/grub"
      end

      def pack_template
        @template.update_attribute :build_state, :packaging

        host.exec "rm #{build_path}/etc/udev/rules.d/70-persistent-cd.rules #{build_path}/etc/udev/rules.d/70-persistent-net.rules #{build_path}/etc/mdadm/mdadm.conf"
        chroot! build_path, "mv /boot /kernel", "Failed to move boot to kernel"
        tar_template build_path, @template
        chroot! build_path, "mv /kernel /boot", "Failed to move kernal back to boot"
      end

      def build_template template, options={}
        return false unless template.build_state == :pending or options[:force]

        @template = template

        template.update_attributes build_state: :running, os_version: os_version
        mkdir_p build_path
        mkdir_p download_path

        steps = [
          ["De-Bootstrap system", :debootstrap_debian],
          ["Update base system", :update_base],
          ["Install kernel", :install_kernel],
          ["Install basic utils", :install_utils],
          ["Install network utils", :install_network],
          ["Install SSH server", :install_ssh],
          ["Install tinc VPN server", :install_tinc],
          ["Install LXD virtualizer", :install_lxd],
          ["Install mailer (exim) for mail out", :install_exim],
          ["Install check_mk agent for monitoring", :install_check_mk_agent],
          ["Install bootloader grub", :install_grub],
          ["Pack template tarball", :pack_template],
          ["Download template tarball", :download_new_template],
          ["Finalize", :finalize_template]
        ]


        if options[:prepend_output]
          puts options[:prepend_output]
        end

        begin
          run_steps :build, steps, options
        rescue Exception => e
          CloudModel.log_exception e
          template.update_attributes build_state: :failed, build_last_issue: "#{e}"
          puts "#{e.class}: #{e.message}"
          e.backtrace.each do |bt|
            puts "\tfrom #{bt}"
          end
          #cleanup_chroot build_path
          raise "Failed to build host image!"
        end

        template.update_attributes build_state: :finished, build_last_issue: ""

        return template
      end
    end
  end
end