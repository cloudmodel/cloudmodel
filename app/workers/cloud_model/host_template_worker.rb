module CloudModel
  class HostTemplateWorker < BaseWorker
    def pack_template build_path, template
      mkdir_p File.dirname(template.tarball)
      build_tar '.', template.tarball, one_file_system: true, exclude: [
        './tmp/*',
        './run/*',
        './var/tmp/*',
        './var/run/*',
        './var/cache/*',
        './usr/share/man',
        './usr/share/doc',
        './etc/ssh/*_key*'
      ], C: build_path
    end
    
    def download_path 
      "/cloud/build/downloads/"
    end
    
    def build_path 
      "/cloud/build/host/#{@template.id}/"
    end
    
    def ubuntu_version 
      "18.04-beta2"
    end
    
    def ubuntu_kernel_flavour
      "generic" #"-lts-xenial"
    end
    
    def ubuntu_arch 
      @template.arch
    end
    
    def ubuntu_image
      "ubuntu-base-#{ubuntu_version}-base-#{ubuntu_arch}.tar.gz"
    end
    
    def ubuntu_url
      if(ubuntu_version =~ /-beta/)
        version = ubuntu_version.split('-')
        "http://cdimage.ubuntu.com/ubuntu-base/releases/#{version[0]}/#{version[1].gsub('beta', 'beta-')}/#{ubuntu_image}"
      else
        "http://cdimage.ubuntu.com/ubuntu-base/releases/#{ubuntu_version}/release/#{ubuntu_image}"
      end
    end
    
    def download_ubuntu
      begin
        @host.sftp.stat!("#{download_path}#{ubuntu_image}")
      rescue
        comment_sub_step "Downloading #{ubuntu_url}"
        @host.exec! "cd #{download_path} && curl #{ubuntu_url.shellescape} -o #{download_path}#{ubuntu_image}", "Failed to download ubuntu image"
      end
    end
      
    def populate_root
      @host.exec! "cd #{build_path} && tar xzpf #{download_path}#{ubuntu_image}", "Failed to unpack system image!"
      # Copy resolv.conf
      @host.exec! "cp /etc/resolv.conf #{build_path}/etc", "Failed to copy resolve conf"
      # Enable universe sources
      @host.exec! "sed -i \"/^# deb.*universe/ s/^# //\" #{build_path}/etc/apt/sources.list", "Failed to activate universe sources"
      @host.exec! "sed -i \"s*http://archive.ubuntu.com/ubuntu/*#{CloudModel.config.ubuntu_mirror}*\" #{build_path}/etc/apt/sources.list", "Failed to set ubutu mirror"
      @host.exec! "sed -i \"s/^deb-src/# deb-src/\" #{build_path}/etc/apt/sources.list", "Failed to set disable deb-src" unless CloudModel.config.ubuntu_deb_src
      # Don't start services on install
      render_to_remote "/cloud_model/support/usr/sbin/policy-rc.d", "#{build_path}/usr/sbin/policy-rc.d", 0755
      # Don't install docs
      render_to_remote  "/cloud_model/support/etc/dpkg/dpkg.cfg.d/01_nodoc", "#{build_path}/etc/dpkg/dpkg.cfg.d/01_nodoc"
    end
    
    def update_base
      chroot! build_path, "dpkg --configure -a && apt-get update && apt-get upgrade -y", "Failed to update sources"
      # Set locale
#      chroot! build_path, "localedef -i en_US -c -f UTF-8 en_US.UTF-8", "Failed to define locale"
 #     chroot! build_path, "update-locale LANG=en_US.UTF-8 LC_MESSAGES=POSIX", "Failed to update locale"
    end 
    
    def install_utils
      comment_sub_step 'Install mdadm'
      chroot! build_path, "apt-get install sudo mdadm -y", "Failed to install mdadm"
      comment_sub_step 'Install btrfs'
      chroot! build_path, "apt-get install sudo btrfs-tools -y", "Failed to install btrfs"
      comment_sub_step 'Install zfs'
      chroot! build_path, "apt-get install sudo zfs-dkms -y", "Failed to install zfs"
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
    
    def install_ssh
      chroot! build_path, "apt-get install ssh -y", "Failed to install SSH"
      # SSH is enabled by default, do no need to enable it by hand
    end
    
    def install_tinc
      chroot! build_path, "apt-get install tinc -y", "Failed to install tinc"
      mkdir_p "#{build_path}/etc/systemd/system/basic.target.wants"
      chroot! build_path, "ln -s /lib/systemd/system/tinc.service /etc/systemd/system/basic.target.wants/tinc.service", "Failed to add tinc to autostart"
      chroot! build_path, "echo vpn >> /etc/tinc/nets.boot", "Failed to add vpn to boot networks of tinc"
    end
    
    def install_lxd
      comment_sub_step 'Install apparmor'
      chroot! build_path, "apt-get install apparmor-utils -y", "Failed to install apparmor"
      comment_sub_step 'Install LXD'
      chroot! build_path, "apt-get install lxd -y", "Failed to install LXD"
      
      mkdir_p "#{build_path}/etc/systemd/system/basic.target.wants"
      chroot! build_path, "ln -s /lib/systemd/system/lxd.service /etc/systemd/system/basic.target.wants/lxd.service", "Failed to add lxd to autostart"
      
      
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
      
    def pack_host_template
      @template.update_attribute :build_state, :packaging
      chroot! build_path, "mv /boot /kernel", "Failed to move boot to kernel"
      pack_template build_path, @template
      chroot! build_path, "mv /kernel /boot", "Failed to move kernal back to boot"      
    end
    
    def download_host_template
      @template.update_attribute :build_state, :downloading
      download_template @template
    end
    
    def finalize_host_template
      @template.update_attribute :build_state, :finished
      cleanup_chroot build_path
      @host.exec "rm -rf #{build_path.shellescape}"
    end
      
    def build_template template, options={}
      return false unless template.build_state == :pending or options[:force]
      
      @template = template
      
      template.update_attributes build_state: :running, os_version: "ubuntu-#{ubuntu_version}"
      
      mkdir_p build_path
      mkdir_p download_path
      
      steps = [
        ["Download Ubutu Base #{ubuntu_version}", :download_ubuntu],
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
        ["Pack template tarball", :pack_host_template],
        ["Download template tarball", :download_host_template],
        ["Finalize", :finalize_host_template]       
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