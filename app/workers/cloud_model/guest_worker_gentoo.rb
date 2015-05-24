module CloudModel
  class GuestWorkerGentoo < GuestWorker
    
    def unpack_root_image
      puts "    Sync Images"
      @host.sync_inst_images
      puts "    Populate System with System Image"
      @host.exec! "cd #{@guest.deploy_path} && tar xpf /inst/guest.tar", "Failed to unpack system image!"
    end

    def config_guest
      puts "  Prepare VM"

      # Setup Net
      begin
        puts "    Write network config"      
        render_to_remote "/cloud_model/guest/etc/conf.d/network", "#{@guest.deploy_path}/etc/conf.d/network@eth0", host: @host, guest: @guest
      rescue Exception => e
        CloudModel.log_exception e
        raise "Failed to configure network!"
      end
      
      begin
        puts "    Write hostname"
        render_to_remote "/cloud_model/support/etc/hostname", "#{@guest.deploy_path}/etc/hostname", host: @guest
        render_to_remote "/cloud_model/support/etc/machine_info", "#{@guest.deploy_path}/etc/machine-info", host: @guest     
      rescue Exception => e
        CloudModel.log_exception e
        raise "Failed to configure hostname!"
      end

      begin
        puts "    Write hosts file"
        @host.sftp.file.open("#{@guest.deploy_path}/etc/hosts", 'w') do | f |
          f.puts "127.0.0.1       localhost"
          f.puts "::1             localhost"
          @host.guests.each do |guest|
            f.puts "#{"%-15s" % guest.private_address} #{guest.name} #{guest.external_hostname}" 
          end
        end
      rescue Exception => e
        CloudModel.log_exception e
        raise "Failed to configure hosts file!"
      end
    
      begin
        puts "    Append prompt to profile file"
        @host.sftp.file.open("#{@guest.deploy_path}/etc/profile", "a") do |f|
          f.puts "if [[ ${EUID} == 0 ]] ; then"
          f.puts "\tPS1='\\[\\033[01;31m\\]#{@guest.name.shellescape}\\[\\033[01;34m\\] \\W \\$\\[\\033[00m\\] '"
          f.puts "else"
          f.puts "\tPS1='\\[\\033[01;32m\\]\\u@#{@guest.name.shellescape}\\[\\033[01;34m\\] \\w \\$\\[\\033[00m\\] '"
          f.puts "fi"
        end
      rescue
        raise "Failed to configure profile file!"
      end      
    end

    # Perhaps also generic
    def config_services
      puts "    Handle and config Services"
      @guest.services.each do |service|
        begin
          puts "      #{service.class.model_name.element.camelcase} '#{service.name}'"
          service_worker_class = "CloudModel::Services::#{service.class.model_name.element.camelcase}Worker".constantize
          service_worker = service_worker_class.new @guest, service
  
          service_worker.write_config
          service_worker.auto_start
        rescue Exception => e
          CloudModel.log_exception e
          raise "Failed to configure service #{service.class.model_name.element.camelcase} '#{service.name}'"
        end
      end
      mkdir_p "#{@guest.deploy_path}/usr/share/cloud_model/"
      render_to_remote "/cloud_model/guest/usr/share/cloud_model/fix_permissions.sh", "#{@guest.deploy_path}/usr/share/cloud_model/fix_permissions.sh", 0755, guest: guest 
    end
    
  end
end