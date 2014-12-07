module CloudModel
  class BaseWorker
    include AbstractController::Rendering
    include ActionView::Helpers::DateHelper

    def initialize(host)
      @host = host
    end
    
    def render template, locals={}
      av = ActionView::Base.new
      av.view_paths = ActionController::Base.view_paths
      av.render(template: template, locals: locals)
    end
    
    # render_to_remote template, remote_file, [[perms], locals]
    def render_to_remote template, remote_file, *param_array
      perm = if param_array.first.is_a? Fixnum
        param_array.shift 
      else
        0600
      end
            
      locals = param_array.pop || {}
      
      # remote_dir = File.dirname remote_file
      # begin
      #   @host.sftp.dir.entries remote_dir
      # rescue Exception => e
      #   puts "Directory #{remote_dir} does not exist, creating it (#{e})"
      #   mkdir_p remote_dir
      # end
      
      content = render(template, locals) 
            
      @host.sftp.file.open(remote_file, 'w', perm) do |f|
        f.puts content
      end
    end
    
    def prepare_chroot chroot_dir, options={}
      @chroot_prepared ||= {}
      
      return true if @chroot_prepared[chroot_dir] and not options[:force]
      
      unless @host.mounted_at? "#{chroot_dir}/proc"
        @host.exec! "mount -t proc none #{chroot_dir}/proc", 'Failed to mount proc to build system'
      end
      unless @host.mounted_at? "#{chroot_dir}/sys"
        @host.exec! "mount --bind /sys #{chroot_dir}/sys", 'Failed to mount sys to build system'
      end
      unless @host.mounted_at? "#{chroot_dir}/dev"
        @host.exec! "mount --bind /dev #{chroot_dir}/dev", 'Failed to mount dev to build system'
      end
      unless @host.mounted_at? "#{chroot_dir}/dev/pts"
        @host.exec! "mount --bind /dev #{chroot_dir}/dev/pts", 'Failed to mount dev to build system'
      end
      
      @chroot_prepared[chroot_dir] = true
    end
    
    def cleanup_chroot chroot_dir
      @chroot_prepared ||= {}

      if @host.mounted_at? "#{chroot_dir}/dev/pts"
        @host.exec! "umount #{chroot_dir}/dev/pts", 'Failed to unmount dev to build system'
      end
      if @host.mounted_at? "#{chroot_dir}/dev"
        @host.exec! "umount #{chroot_dir}/dev", 'Failed to unmount dev to build system'
      end
      if @host.mounted_at? "#{chroot_dir}/sys"
        @host.exec! "umount #{chroot_dir}/sys", 'Failed to unmount sys to build system'
      end
      if @host.mounted_at? "#{chroot_dir}/proc"
        @host.exec! "umount #{chroot_dir}/proc", 'Failed to unmount proc to build system'
      end
      
      @chroot_prepared[chroot_dir] = false
      
      true
    end
    
    def chroot chroot_dir, command
      key = SecureRandom.uuid
      Rails.logger.debug "CHROOT: #{chroot_dir}: #{command}"
      
      prepare_chroot chroot_dir
      
      render_to_remote "/cloud_model/support/chroot.sh", "#{chroot_dir}/root/chroot-#{key}.sh", 0700, command: command        
      result = @host.exec "chroot #{chroot_dir} /root/chroot-#{key}.sh"
      begin
        @host.sftp.remove! "#{chroot_dir}/root/chroot-#{key}.sh"
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
    
    def run_steps stage, steps, options={}
      indent = options[:indent] || 2
      
      counter_prefix = options[:counter_prefix] || ''
      counter = 0
      
      skip_to_string = options[:skip_to] || ''
      if skip_splitted = /^(\d+)\.?(.*)/.match(skip_to_string.to_s)
        skip_to_string = skip_splitted[2]
        skip_to = skip_splitted[1].to_i
      else
        skip_to_string = ''
        skip_to = 0
      end
      
      steps.each do |step|
        counter += 1
        
        step = [step.to_s.humanize, step] if step.class == Symbol
        
        print "#{' ' * indent}(#{counter_prefix}#{counter}) #{step[0]}"
        
        if skip_to > counter
          if step[2] and step[2][:on_skip]
            print " (Run skip action)"
            begin
              ts = Time.now
              self.send step[2][:on_skip]
              puts " [Done in #{distance_of_time_in_words_to_now ts}]"
            rescue
              puts " [Failed after #{distance_of_time_in_words_to_now ts}]"
              puts ''
              CloudModel.log_exception e
              @host.update_attributes :"#{stage}_state" => :failed, :"#{stage}_last_issue" => "#{e}"
              raise e
              
            end
          else
            puts " [Skipped]"
          end
        else
          if step[1].class == Array
            puts ''
            run_steps stage, step[1], options.merge(
              indent: indent+2, 
              counter_prefix: "#{counter_prefix}#{counter}.",
              skip_to: skip_to == counter ? skip_to_string : ''
            )
          else
            begin
              ts = Time.now
              self.send step[1]   
              puts " [Done in #{distance_of_time_in_words_to_now ts}]"   
            rescue Exception => e
              if e.class == RuntimeError and e.message == 'skipped'
                puts " [Skipped]"
              else
                puts " [Failed after #{distance_of_time_in_words_to_now ts}]"
                puts ''
                CloudModel.log_exception e
                @host.update_attributes :"#{stage}_state" => :failed, :"#{stage}_last_issue" => "#{e}"
                raise e
              end
            end
          end
        end
      end   
    end
    
  end
end