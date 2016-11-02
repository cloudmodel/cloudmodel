module CloudModel
  class GuestTemplateWorker < BaseWorker
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
    
    def build_core_template template, options={}
      ubuntu_version = "16.04.1"
      ubuntu_arch = template.arch
      ubuntu_image = "ubuntu-base-#{ubuntu_version}-base-#{ubuntu_arch}.tar.gz"
      ubuntu_url = "http://cdimage.ubuntu.com/ubuntu-base/releases/#{ubuntu_version}/release/#{ubuntu_image}"

      build_path = "/inst/templates/build/core/#{template.id}"
      
      return false unless template.build_state == :pending or options[:force]
      template.update_attributes build_state: :running, os_version: "ubuntu-#{ubuntu_version}"
      
      begin  
        mkdir_p build_path
      
        begin
          @host.sftp.stat!("/inst/#{ubuntu_image}")
        rescue
          puts "    Download Ubutu Core #{ubuntu_version}"
          @host.exec! "cd /inst && curl #{ubuntu_url.shellescape} -o /inst/#{ubuntu_image}", "Failed to download ubuntu image"
        end

        puts "    Populate system with image"
        @host.exec! "cd #{build_path} && tar xzpf /inst/#{ubuntu_image}", "Failed to unpack system image!"
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

        # Update package list
        puts "    Update core system"
        chroot! build_path, "apt-get update && apt-get upgrade -y", "Failed to update sources"
      
        # Autologin
        puts "    Config autologin"
        mkdir_p "#{build_path}/etc/systemd/system/console-getty.service.d"
        render_to_remote "/cloud_model/guest/etc/systemd/system/console-getty.service.d/autologin.conf", "#{build_path}/etc/systemd/system/console-getty.service.d/autologin.conf"
      
        # Set locale
        chroot! build_path, "localedef -i en_US -c -f UTF-8 en_US.UTF-8", "Failed to define locale"
        chroot! build_path, "update-locale LANG=en_US.UTF-8 LC_MESSAGES=POSIX", "Failed to update locale"
     
        # Tool for setting serial console size in terminal; call on virsh console to fix terminal size
        render_to_remote "/cloud_model/guest/bin/fixterm.sh", "#{build_path}/bin/fixterm", 0755   
    
        puts "    Install network base system"
        chroot! build_path, "apt-get install netbase -y", "Failed to install network base system"
      
        puts "    Install SSH"
        chroot! build_path, "apt-get install ssh -y", "Failed to install SSH"
      
        puts "    Install check_mk-agent"
        chroot! build_path, "apt-get install check-mk-agent -y", "Failed to install CheckMKAgent"
        render_to_remote "/cloud_model/guest/etc/systemd/system/check_mk@.service", "#{build_path}/etc/systemd/system/check_mk@.service"     
        render_to_remote "/cloud_model/guest/etc/systemd/system/check_mk.socket", "#{build_path}/etc/systemd/system/check_mk.socket"     
        mkdir_p "#{build_path}/etc/systemd/system/sockets.target.wants"
        chroot! build_path, "ln -s /etc/systemd/system/check_mk.socket /etc/systemd/system/sockets.target.wants/check_mk.socket", "Failed to add check_mk to autostart"
        %w(cgroup_mem cgroup_cpu).each do |sensor|
          render_to_remote "/cloud_model/support/usr/lib/check_mk_agent/#{sensor}", "#{build_path}/usr/lib/check_mk_agent/#{sensor}", 0755 
        end
        render_to_remote "/cloud_model/support/usr/sbin/cgroup_load_writer", "#{build_path}/usr/sbin/cgroup_load_writer", 0755 
        render_to_remote "/cloud_model/guest/etc/systemd/system/cgroup_load_writer.service", "#{build_path}/etc/systemd/system/cgroup_load_writer.service"     
        render_to_remote "/cloud_model/guest/etc/systemd/system/cgroup_load_writer.timer", "#{build_path}/etc/systemd/system/cgroup_load_writer.timer"     
        chroot! build_path, "ln -s /etc/systemd/system/cgroup_load_writer.timer /etc/systemd/system/timers.target.wants/cgroup_load_writer.timer"      
      
        puts '    Packaging'
        template.update_attribute :build_state, :packaging
        pack_template build_path, template
        
        puts '    Downloading'
        template.update_attribute :build_state, :downloading
        download_template template
        
        template.update_attribute :build_state, :finished
      rescue Exception => e
        CloudModel.log_exception e
        template.update_attributes build_state: :failed, build_last_issue: "#{e}"
        cleanup_chroot build_path
        raise "Failed to build core image!"
      end
      
      puts "    Cleanup"
      cleanup_chroot build_path
      @host.exec "rm -rf #{build_path.shellescape}"
      
      return template
    end
    
    def build_template(template, options={})
      return false unless template.build_state == :pending or options[:force]
      template.update_attribute :build_state, :running
    
      begin
        build_path = "/inst/templates/build/#{template.template_type.id}/#{template.id}"      
        
        mkdir_p build_path
                
        begin
          @host.sftp.stat!("#{template.core_template.tarball}")
        rescue
          puts '      Uploading template'
          upload_template template.core_template
        end
        @host.exec! "cd #{build_path} && tar xvf #{template.core_template.tarball.shellescape}", "Failed to unpack core template"
        
        template.template_type.components.each do |component_type|
          begin
            component_const = "CloudModel::Components::#{component_type.to_s.gsub(/[^a-z0-9]*/, '').camelcase}Worker".constantize
            component = component_const.new @host
          rescue Exception => e
            CloudModel.log_exception e
            raise "Component :#{component_type} has no worker"
          end      
          component.build build_path
        end
      
        puts '    Packaging'
        template.update_attribute :build_state, :packaging
        pack_template build_path, template
        
        puts '    Downloading'
        template.update_attribute :build_state, :downloading
        download_template template
        
        template.update_attribute :build_state, :finished
      rescue Exception => e
        CloudModel.log_exception e
        template.update_attributes build_state: :failed, build_last_issue: "#{e}"
        cleanup_chroot build_path
        raise "Failed to build core image!"
      end
      
      puts "    Cleanup"
      cleanup_chroot build_path
      @host.exec "rm -rf #{build_path.shellescape}"
      
      return template
    end
  end
end
