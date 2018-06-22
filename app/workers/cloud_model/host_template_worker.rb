module CloudModel
  class HostTemplateWorker < TemplateWorker    
    def build_path 
      "/cloud/build/host/#{@template.id}/"
    end
              
    def install_utils
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
      comment_sub_step 'Install curl'
      chroot! build_path, "apt-get install sudo curl -y", "Failed to install curl"
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
      comment_sub_step 'Install apparmor'
      chroot! build_path, "apt-get install apparmor-utils -y", "Failed to install apparmor"
      comment_sub_step 'Install LXD'
      chroot! build_path, "apt-get install lxd -y", "Failed to install LXD"
      
      mkdir_p "#{build_path}/etc/systemd/system/basic.target.wants"
      #mkdir_p "#{build_path}/etc/systemd/system/sockets.target.wants"
      #chroot! build_path, "ln -s /lib/systemd/system/lxd.socket /etc/systemd/system/sockets.target.wants/lxd.socket", "Failed to add lxd to autostart"
      chroot! build_path, "ln -s /lib/systemd/system/lxd-containers.service /etc/systemd/system/basic.target.wants/lxd-containers.service", "Failed to add lxd to autostart"
      
      
      comment_sub_step 'Create guests directory'
      mkdir_p "#{build_path}/cloud/guests"      
    end
    
    def install_exim
      chroot! build_path, "apt-get install exim4 -y", "Failed to install Exim"

      mkdir_p "#{build_path}/etc/systemd/system/basic.target.wants"
      chroot! build_path, "ln -s /lib/systemd/system/exim4.service /etc/systemd/system/basic.target.wants/exim4.service", "Failed to add exim to autostart"
    end
    
    def install_check_mk_agent
      chroot! build_path, "apt-get install check-mk-agent -y", "Failed to install CheckMKAgent"
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
      chroot! build_path, "apt-get install linux-image-#{ubuntu_kernel_flavour} -y", "Failed to install Exim"
    end
    
    def install_grub
      chroot! build_path, "apt-get install grub2 -y", "Failed to install Grub"
      render_to_remote "/cloud_model/host/etc/default/grub", "#{build_path}/etc/default/grub"      
    end
      
    def pack_template
      @template.update_attribute :build_state, :packaging
      chroot! build_path, "mv /boot /kernel", "Failed to move boot to kernel"
      tar_template build_path, @template
      chroot! build_path, "mv /kernel /boot", "Failed to move kernal back to boot"      
    end
          
    def build_template template, options={}
      return false unless template.build_state == :pending or options[:force]
      
      @template = template
      
      template.update_attributes build_state: :running, os_version: "ubuntu-#{ubuntu_version}"
      
      mkdir_p build_path
      mkdir_p download_path
      
      steps = [
        ["Download Ubutu Base #{ubuntu_version}", :fetch_ubuntu],
        ["Populate system with image", :populate_root],
        ["Update base system", :update_base],
        ["Install basic utils", :install_utils],
        ["Install network utils", :install_network],
        ["Install SSH server", :install_ssh],
        ["Install tinc VPN server", :install_tinc],
        ["Install LXD virtualizer", :install_lxd],
        ["Install mailer (exim) for mail out", :install_exim],
        ["Install check_mk agent for monitoring", :install_check_mk_agent],
        ["Install kernel", :install_kernel],
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
        cleanup_chroot build_path
        raise "Failed to build host image!"
      end
      
      template.update_attributes build_state: :finished, build_last_issue: ""
      
      return template
    end
  end
end