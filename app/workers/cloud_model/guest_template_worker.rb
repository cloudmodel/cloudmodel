module CloudModel
  class GuestTemplateWorker < TemplateWorker
    
    def build_path
      if @template.is_a? CloudModel::GuestCoreTemplate
        "/cloud/build/core/#{@template.id}"
      else
        "/cloud/build/#{@template.template_type.id}/#{@template.id}"      
      end
    end
    
    def install_utils
      comment_sub_step 'Install gnupg'
      chroot! build_path, "apt-get install sudo gnupg -y", "Failed to install gnupg"
      
      comment_sub_step 'Configre autologin'
      # Autologin
      mkdir_p "#{build_path}/etc/systemd/system/console-getty.service.d"
      render_to_remote "/cloud_model/guest/etc/systemd/system/console-getty.service.d/autologin.conf", "#{build_path}/etc/systemd/system/console-getty.service.d/autologin.conf"
         
      comment_sub_step 'Apply fixterm patch'
      # Tool for setting serial console size in terminal; call on virsh console to fix terminal size
      render_to_remote "/cloud_model/guest/bin/fixterm.sh", "#{build_path}/bin/fixterm", 0755   
    end
    
    def install_network
      comment_sub_step 'Install netbase'
      chroot! build_path, "apt-get install netbase iproute2 -y", "Failed to install network base"
    end
    
    def install_check_mk_agent
      chroot! build_path, "apt-get install check-mk-agent -y", "Failed to install CheckMKAgent"
      render_to_remote "/cloud_model/guest/etc/systemd/system/check_mk@.service", "#{build_path}/etc/systemd/system/check_mk@.service"     
      render_to_remote "/cloud_model/guest/etc/systemd/system/check_mk.socket", "#{build_path}/etc/systemd/system/check_mk.socket"     
      mkdir_p "#{build_path}/etc/systemd/system/sockets.target.wants"
      chroot! build_path, "ln -s /etc/systemd/system/check_mk.socket /etc/systemd/system/sockets.target.wants/check_mk.socket", "Failed to add check_mk to autostart"

      %w(cgroup_mem cgroup_cpu).each do |sensor|
        render_to_remote "/cloud_model/support/usr/lib/check_mk_agent/plugins/#{sensor}", "#{build_path}/usr/lib/check_mk_agent/plugins/#{sensor}", 0755 
      end
      
      render_to_remote "/cloud_model/support/usr/sbin/cgroup_load_writer", "#{build_path}/usr/sbin/cgroup_load_writer", 0755 
      render_to_remote "/cloud_model/guest/etc/systemd/system/cgroup_load_writer.service", "#{build_path}/etc/systemd/system/cgroup_load_writer.service"     
      render_to_remote "/cloud_model/guest/etc/systemd/system/cgroup_load_writer.timer", "#{build_path}/etc/systemd/system/cgroup_load_writer.timer"     
      chroot! build_path, "ln -s /etc/systemd/system/cgroup_load_writer.timer /etc/systemd/system/timers.target.wants/cgroup_load_writer.timer", "Failed to enable cgroup_load_writer service"     
    end
    
    def pack_template
      @template.update_attribute :build_state, :packaging
      tar_template build_path, @template
    end
    
    
    
    def build_core_template template, options={}     
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
        ["Install check_mk agent for monitoring", :install_check_mk_agent],  
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
        raise "Failed to build core image!"
      end
      
      template.update_attributes build_state: :finished, build_last_issue: ""
      
      return template      
    end
    
    #---
    
    def fetch_core_template
      begin
        @host.sftp.stat!("#{@template.core_template.tarball}")
      rescue
        comment_sub_step "Downloading core template"
        upload_template @template.core_template
      end
      @host.exec! "cd #{build_path} && tar xvf #{@template.core_template.tarball.shellescape}", "Failed to unpack core template"
      # Copy resolv.conf
      @host.exec! "rm #{build_path}/etc/resolv.conf", "Failed to remove old resolve conf"
      @host.exec! "cp /etc/resolv.conf #{build_path}/etc", "Failed to copy resolve conf"
    end
    
    def install_components
      @template.template_type.components.each do |component_type|
        begin
          comment_sub_step "Install #{component_type}"
          component_const = "CloudModel::Components::#{component_type.to_s.gsub(/[^a-z0-9]*/, '').camelcase}Worker".constantize
          component = component_const.new @host
        rescue Exception => e
          CloudModel.log_exception e
          raise "Component :#{component_type} has no worker"
        end      
        component.build build_path
      end
    end
    
    def build_template(template, options={})
      return false unless template.build_state == :pending or options[:force]
      
      @template = template
      
      template.update_attributes build_state: :running
      
      mkdir_p build_path
      mkdir_p download_path
      
      steps = [
        ["Download Core Template #{@template.core_template.id}", :fetch_core_template],
        ["Install Components", :install_components],
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
        raise "Failed to build core image!"
      end
      
      template.update_attributes build_state: :finished, build_last_issue: ""
      
      return template      
      #----
    
      begin
                

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
