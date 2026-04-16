module CloudModel
  module Workers
    # Minimal host stub used by {KeysWorker}, which does not operate on a real host.
    class MockHost
      def update_attributes attrs
        Rails.logger.debug attrs
      end
    end

    # Abstract base class for all CloudModel workers.
    #
    # Workers execute multi-step tasks on remote hosts via Net::SSH/SFTP. The
    # base class provides:
    # - ERB template rendering ({#render}, {#render_to_remote})
    # - chroot execution ({#chroot}, {#chroot!}) with automatic bind-mount
    #   management ({#prepare_chroot}, {#cleanup_chroot})
    # - Template archive transfer ({#upload_template}, {#download_template})
    # - Stepped task execution with skip-to, per-item iteration, and error
    #   propagation ({#run_steps}, {#run_step_command})
    # - Progress output helpers ({#comment_sub_step}, {#debug})
    class BaseWorker
      include AbstractController::Rendering
      include ActionView::Helpers::DateHelper

      def initialize host, options={}
        @host = host
        @options = options
      end

      # @return [CloudModel::Host] the host this worker operates on
      def host
        @host
      end

      # @return [Object] the model object whose deploy/build state is updated on failure
      def error_log_object
        host
      end

      # Converts a template path to a form acceptable to Rails 7+ view lookup
      # by replacing dots with underscores.
      # @param template [String] original template path
      # @return [String] sanitised template path
      def translate_template_name template
        # Needed for Rails 7+
        template.gsub('.', '_')
      end

      # Renders an ERB template to a string using ActionController rendering.
      # @param template [String] view template path (without extension)
      # @param locals [Hash] local variables passed to the template
      # @return [String] rendered content
      def render template, locals={}
        ActionController::Base.new.render_to_string(template: "#{translate_template_name template}", locals: locals, layout: false)
      end

      # @param template [String] view template path
      # @return [Boolean] whether the template exists in the view lookup path
      def template_exists? template
        not ActionController::Base.new.lookup_context.find_all(translate_template_name template).blank?
      end

      # Renders a template and uploads the result to the remote host via SFTP.
      #
      # @overload render_to_remote(template, remote_file, perm, locals)
      #   @param perm [Integer] file permission (e.g. `0644`)
      # @overload render_to_remote(template, remote_file, locals)
      #   Uses default permission `0600`
      def render_to_remote template, remote_file, *param_array
        perm = if param_array.first.is_a? Integer
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

      # Bind-mounts proc, sys, dev, and dev/pts into a chroot directory so that
      # package managers and other tools work correctly inside the chroot.
      # Results are cached per directory; pass `force: true` to redo.
      # @param chroot_dir [String] path to the chroot root
      # @param options [Hash] pass `force: true` to remount even if already done
      def prepare_chroot chroot_dir, options={}
        @chroot_prepared ||= {}
        chroot_dir = chroot_dir.gsub(/[\/]$/, '') # Remove tailing slashes from path

        #puts @host.exec "ls #{chroot_dir}/dev"

        return true if @chroot_prepared[chroot_dir] and not options[:force]

        unless @host.mounted_at? "#{chroot_dir}/proc"
          mkdir_p "#{chroot_dir}/proc"
          @host.exec! "mount -t proc none #{chroot_dir}/proc", 'Failed to mount proc to build system'
        end
        unless @host.mounted_at? "#{chroot_dir}/sys"
          mkdir_p "#{chroot_dir}/sys"
          # @host.exec! "mount --bind /sys #{chroot_dir}/sys", 'Failed to mount sys to build system'
          @host.exec! "mount -t sysfs sys #{chroot_dir}/sys", 'Failed to mount sys to build system'
        end
        unless @host.mounted_at? "#{chroot_dir}/dev"
          mkdir_p "#{chroot_dir}/dev"
          @host.exec! "mount --bind /dev #{chroot_dir}/dev", 'Failed to mount dev to build system'
        end
        unless @host.mounted_at? "#{chroot_dir}/dev/pts"
          # @host.exec! "mount --bind /dev/pts #{chroot_dir}/dev/pts", 'Failed to mount dev/pts to build system'
          @host.exec! "mount -t devpts pts #{chroot_dir}/dev/pts", 'Failed to mount dev/pts to build system'
        end

        @chroot_prepared[chroot_dir] = true
      end

      # Unmounts proc, sys, dev/pts, and dev from a chroot directory.
      # @param chroot_dir [String] path to the chroot root
      # @return [true]
      def cleanup_chroot chroot_dir
        @chroot_prepared ||= {}
        chroot_dir = chroot_dir.gsub(/[\/]$/, '') # Remove tailing slashes from path

        if @host.mounted_at? "#{chroot_dir}/dev/pts"
          @host.exec! "umount #{chroot_dir}/dev/pts", 'Failed to unmount dev/pts from build system'
        end
        if @host.mounted_at? "#{chroot_dir}/dev"
          @host.exec! "umount #{chroot_dir}/dev", 'Failed to unmount dev from build system'
        end
        if @host.mounted_at? "#{chroot_dir}/sys"
          @host.exec! "umount #{chroot_dir}/sys", 'Failed to unmount sys from build system'
        end
        if @host.mounted_at? "#{chroot_dir}/proc"
          @host.exec! "umount #{chroot_dir}/proc", 'Failed to unmount proc from build system'
        end

        @chroot_prepared[chroot_dir] = false

        true
      end

      # Executes a shell command inside a chroot by rendering a wrapper script,
      # uploading it, running it, and then removing it.
      # @param chroot_dir [String] path to the chroot root
      # @param command [String] shell command to run inside the chroot
      # @return [Array(Boolean, String)] success flag and command output
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

      # Like {#chroot} but raises on failure.
      # @param chroot_dir [String] path to the chroot root
      # @param command [String] shell command to run inside the chroot
      # @param message [String] error message prefix on failure
      # @return [String] command output
      # @raise [RuntimeError] if the command exits with a non-zero status
      def chroot! chroot_dir, command, message
        success, data = chroot chroot_dir, command

        unless success
          raise "#{message}: #{data}"
        end
        data
      end

      # Creates a directory (and parents) on the remote host.
      # @param path [String] remote directory path to create
      def mkdir_p path
        @host.exec! "mkdir -p #{path.shellescape}", "Failed to make directory #{path}"
      end

      # Runs a shell command locally on the CloudModel controller machine.
      # @param command [String] shell command
      # @return [String] combined stdout/stderr output
      def local_exec command
        Rails.logger.debug "LOKAL EXEC: #{command}"
        result = %x(#{command} 2>&1)
        Rails.logger.debug "    #{result}"
        result
      end

      # Like {#local_exec} but raises on non-zero exit.
      # @param command [String] shell command
      # @param message [String] error message prefix on failure
      # @return [String] command output
      # @raise [RuntimeError] if the command fails
      def local_exec! command, message
        result = local_exec command

        unless $?.success?
          raise "#{message}: #{result}"
        end
        result
      end

      # Downloads a built template tarball from the remote host to the local
      # data directory using SCP. Skips if `skip_sync_images` is configured.
      # @param template [CloudModel::GuestTemplate, CloudModel::HostTemplate] the template to download
      def download_template template
        return if CloudModel.config.skip_sync_images
        # Download build template to local distribution
        tarball_target = "#{CloudModel.config.data_directory}#{template.tarball}"
        FileUtils.mkdir_p File.dirname(tarball_target)
        command = "scp -C -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa root@#{@host.ssh_address}:#{template.tarball.shellescape} #{tarball_target.shellescape}"
        Rails.logger.debug command
        local_exec! command, "Failed to download archived template"
      end

      # Uploads a local template tarball to the remote host using SCP.
      # Skips if `skip_sync_images` is configured.
      # @param template [CloudModel::GuestTemplate, CloudModel::HostTemplate] the template to upload
      def upload_template template
        return if CloudModel.config.skip_sync_images
        # Upload build template to host
        srcball_target = "#{CloudModel.config.data_directory}#{template.tarball}"
        mkdir_p File.dirname(template.tarball)
        command = "scp -C -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa #{srcball_target.shellescape} root@#{@host.ssh_address}:#{template.tarball.shellescape}"
        Rails.logger.debug command
        local_exec! command, "Failed to upload built template"
      end

      def upsync_templates
        return if CloudModel.config.skip_sync_images
        command = "rsync -avz -e 'ssh -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa' #{CloudModel.config.data_directory.shellescape}/inst/templates root@#{@host.ssh_address}:/inst/templates"
        Rails.logger.debug command
        local_exec! command, 'Failed to upsync templates'
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

        cmd = "/bin/tar czf #{dst.shellescape} "

        options.each do |k,v|
          param = k.to_s.gsub('_', '-').shellescape

          cmd << parse_param(param, v)
        end
        cmd << "#{src.shellescape}"

        @host.exec! cmd, "Failed to build tar #{dst}"
      end

      def run_step_command stage, command, step, options
        skip_to_string, skip_to = parse_step_skip_to options[:skip_to]

        ts = Time.now

        begin
          if step[2] and step[2][:each]
            puts ':'
            indent = options[:indent] || 2

            counter_prefix = options[:counter_prefix] || ''
            counter = 0

            step[2][:each].each do |object|
              counter += 1
              print "#{' ' * indent}(#{counter_prefix}#{counter}) For #{object.name}"

              if skip_to > counter
                puts "[Skipped*]"
              else
                if options[:pretend]
                  puts "[Done (pretended)]"
                else
                  ts = Time.now
                  self.send step[1], object
                  #self.send command, object
                  puts "[Done in #{distance_of_time_in_words_to_now ts}]"
                end
              end
            end
          else
            if options[:pretend]
              puts "[Done (pretended)]"
            else
              ts = Time.now
              #self.send step[1]
              self.send command
              puts "[Done in #{distance_of_time_in_words_to_now ts}]"
              Rails.logger.debug "STEP FINISH: (#{counter_prefix}#{counter}) #{step[0]}, #{Time.now - ts}"
            end
          end
        rescue Exception => e
          if e.class == RuntimeError and e.message == 'skipped'
            puts "[Skipped]"
          else
            puts "[Failed after #{distance_of_time_in_words_to_now ts}]"
            puts ''
            Rails.logger.debug "STEP FAILED: (#{counter_prefix}#{counter}) #{step[0]}, #{Time.now - ts}"
            CloudModel.log_exception e
            error_log_object.update_attributes :"#{stage}_state" => :failed, :"#{stage}_last_issue" => "#{e}"
            raise e
          end
        end
      end

      def parse_step_skip_to skip_to_string = ''
        if skip_splitted = /^(\d+)\.?(.*)/.match(skip_to_string.to_s)
          skip_to_string = skip_splitted[2]
          skip_to = skip_splitted[1].to_i
        else
          skip_to_string = ''
          skip_to = 0
        end

        [skip_to_string, skip_to]
      end

      def current_indent
        @current_indent ||= 2
      end

      def set_indent indent
        unless indent.blank?
          @current_indent = indent
        end
      end

      def increase_indent
        @current_indent = current_indent + 2
      end

      def decrease_indent
        @current_indent = current_indent - 2
      end

      def current_counter_prefix
        @current_counter_prefix
      end

      def current_counter_prefix=prefix
        @current_counter_prefix=prefix
      end

      def debug message
        puts ""
        print "#{' ' * (current_indent + 4)} [#{message}] "
      end

      def comment_sub_step message, options = {}
        comment_indent = options[:indent] || 2
        puts ""
        print "#{' ' * (current_indent + comment_indent)}* #{message} "
      end

      def run_steps stage, steps, options={}
        set_indent options[:indent]

        counter_prefix = options[:counter_prefix] || ''
        counter = 0

        skip_to_string, skip_to = parse_step_skip_to options[:skip_to]

        steps.each do |step|
          counter += 1

          current_counter_prefix = "#{counter_prefix}#{counter}."

          step_options = options.merge(
            #indent: indent+2,
            counter_prefix: current_counter_prefix,
            skip_to: skip_to == counter ? skip_to_string : ''
          )

          step = [step.to_s.humanize, step] if step.class == Symbol

          print "#{' ' * current_indent}(#{counter_prefix}#{counter}) #{step[0]} "
          Rails.logger.debug "STEP START: (#{counter_prefix}#{counter}) #{step[0]}"

          if skip_to > counter and not (step[2] and step[2][:no_skip])
            if step[2] and step[2][:on_skip]
              print "(Run skip action #{step[2][:on_skip]})"
              run_step_command stage, step[2][:on_skip], step, step_options
            else
              puts "[Skipped]"
            end
          else
            if step[1].class == Array
              puts ':'
              increase_indent
              run_steps stage, step[1], step_options
              decrease_indent
            else
              run_step_command stage, step[1], step, step_options
            end
          end


        end
      end

    end
  end
end