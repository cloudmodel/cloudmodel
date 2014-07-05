module CloudModel
  class BaseWorker
    include AbstractController::Rendering
    
    def render template, locals={}
      av = ActionView::Base.new
      av.view_paths = ActionController::Base.view_paths
      av.render(template: template, locals: locals)
    end
    
    # render_to_remote template, remote_file, [[perms], locals]
    def render_to_remote template, remote_file, *param_array
      locals = param_array.pop || {}
      perm = param_array.first || 0600

      @host.ssh_connection.sftp.file.open(remote_file, 'w', perm) do |f|
        f.puts render(template, locals)
      end
    end
    
    def chroot chroot_dir, command
      key = SecureRandom.uuid
      Rails.logger.debug "CHROOT: #{chroot_dir}: #{command}"
      render_to_remote "/cloud_model/support/chroot.sh", "#{chroot_dir}/root/chroot-#{key}.sh", 0700, command: command        
      result = @host.exec "chroot #{chroot_dir} /root/chroot-#{key}.sh"
      begin
        @host.ssh_connection.sftp.remove! "#{chroot_dir}/root/chroot-#{key}.sh"
      rescue
        Rails.logger.error "Failed to remove remote file #{chroot_dir}/root/chroot-#{key}.sh"
      end
      result
    end
    
    def chroot! chroot_dir, command, message
      success, data = chroot chroot_dir, command

      unless success
        raise "#{message}: #{data}"
      end
      data
    end
    
    def mkdir_p path
      @host.exec! "mkdir -p #{path.shellescape}", "Failed to make directory #{path}"
    end
    
    def local_exec command
      Rails.logger.debug "LOKAL EXEC: #{command}"
      result = `#{command}`
      Rails.logger.debug "    #{result}"
      result
    end
  
    def build_tar src, dst, options = {}
      def parse_param param, value
        params = ''

        if value == true
          params << "-#{param.size>1 ? '-' : ''}#{param} "
        elsif value.class == Array
          value.each do |i|
            params << parse_param(param, i)
          end
        else
          params << "-#{param.size>1 ? '-' : ''}#{param} #{value.shellescape} "
        end

        params
      end

      cmd = "tar cf #{dst.shellescape} "

      options.each do |k,v|
        param = k.to_s.gsub('_', '-').shellescape

        cmd << parse_param(param, v)
      end
      cmd << "#{src.shellescape}"

      @host.exec! cmd, "Failed to build tar #{dst}"
    end
  end
end