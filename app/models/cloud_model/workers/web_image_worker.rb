module CloudModel
  module Workers
    class WebImageWorker < BaseWorker

      def initialize(web_image)
        @web_image = web_image
      end

      def checkout_git
        puts "git clone #{@web_image.git_server.shellescape}:#{@web_image.git_repo.shellescape} #{@web_image.build_path.shellescape}"
        unless File.directory?(@web_image.build_path)
          unless FileUtils.mkdir_p @web_image.build_path
            raise "Could not make checkout directory '#{@web_image.build_path}'"
            return false
          end

          begin
            run_with_clean_env "Cloning", "git clone #{@web_image.git_server.shellescape}:#{@web_image.git_repo.shellescape} #{@web_image.build_path.shellescape}"
          rescue Exception => e
            puts e.trace
            CloudModel.log_exception e
            @web_image.update_attributes build_state: :failed, build_last_issue: "Unable to clone repository '#{@web_image.git_repo}'."
            FileUtils.rm_rf @web_image.build_path
            return false
          end
        end

        git_script = "cd #{@web_image.build_path.shellescape} && "
        git_script += "git checkout #{@web_image.git_branch.shellescape} &&"
        git_script += "git pull"

        begin
          run_with_clean_env "Pulling", git_script
        rescue CloudModel::ExecutionException => e
          CloudModel.log_exception e
          @web_image.update_attributes build_state: :failed, build_last_issue: "Unable to checkout branch '#{@web_image.git_branch}' on repository '#{@web_image.git_repo}'."
          return false
        end

        begin
          @web_image.update_attribute :git_commit, run_with_clean_env("Get Version", "cd #{@web_image.build_path} && git log | head -1 | sed s/'commit '//")
        rescue Exception => e
          CloudModel.log_exception e
          @web_image.update_attribute :git_commit,  "failed to get commit hash"
        end

        return true
      end

      def bundle_image
        begin
          run_with_clean_env "Bundling", [
            "cd #{@web_image.build_path.shellescape}",
            "#{CloudModel.config.bundle_command} config set --local deployment 'true'",
            "#{CloudModel.config.bundle_command} config set --local path './bundle'",
            "#{CloudModel.config.bundle_command} config set --local without 'development test'",
            "#{CloudModel.config.bundle_command} install",
            "#{CloudModel.config.bundle_command} clean"
          ] * ' && '

          #run_with_clean_env "Bundling", "cd #{@web_image.build_path.shellescape} && #{CloudModel.config.bundle_command} install --gemfile #{@web_image.build_path.shellescape}/Gemfile --path ./bundle --deployment --without development test"
        rescue CloudModel::ExecutionException => e
          CloudModel.log_exception e
          @web_image.update_attributes build_state: :failed, build_last_issue: 'Unable to build image.'
          FileUtils.rm_rf @web_image.build_gem_home
          return false
        end

        return true
      end

      def yarn_install
        begin
          run_with_clean_env "Yarn install", [
            "cd #{@web_image.build_path.shellescape}",
            "npm install -g yarn",
            "yarn install --production --non-interactive --modules-folder #{@web_image.build_path.shellescape}/node_modules"
          ] * ' && '
        rescue CloudModel::ExecutionException => e
          CloudModel.log_exception e
          @web_image.update_attributes build_state: :failed, build_last_issue: 'Unable to install yarn packages.'
          FileUtils.rm_rf @web_image.build_gem_home
          return false
        end
        return true
      end

      def build_assets
        begin
          FileUtils.rm_rf "#{@web_image.build_path}/public/assets"

          run_with_clean_env "Building Assets", "cd #{@web_image.build_path.shellescape} && #{CloudModel.config.bundle_command} exec rake RAILS_ENV=production RAILS_GROUPS=assets assets:precompile"
        rescue CloudModel::ExecutionException => e
          CloudModel.log_exception e
          @web_image.update_attributes build_state: :failed, build_last_issue: 'Unable to build assets.'
          FileUtils.rm_rf "#{@web_image.build_path}/public/assets"
          return false
        end

        return true
      end

      def package_build
        begin
          run_within_build_env "Packaging", "/bin/tar -cpjf #{@web_image.build_path.shellescape}-building.tar.bz2 --directory #{@web_image.build_path.shellescape} --exclude={'.git','./.gitignore','./tmp/**/*','./log/**/*','./spec','./features','.rspec','.gitkeep','./bundle/#{Bundler.ruby_scope}/cache','.bundle/#{Bundler.ruby_scope}/doc'} ."
        rescue CloudModel::ExecutionException => e
          CloudModel.log_exception e
          @web_image.update_attributes build_state: :failed, build_last_issue: 'Unable to package image.'
          return false
        end
        FileUtils.mv "#{@web_image.build_path}-building.tar.bz2", "#{@web_image.build_path}.tar.bz2"

        return true
      end

      def build options = {}
        return false unless @web_image.build_state == :pending or options[:force]
        @web_image.update_attributes build_state: :running, build_last_issue: nil

        if options[:clean]
          FileUtils.rm_rf @web_image.build_path
        end

        begin
          @web_image.update_attributes build_state: :checking_out
          unless checkout_git
            return false
          end

          @web_image.update_attributes build_state: :bundling
          if File.file? "#{@web_image.build_path.shellescape}/Gemfile"
            unless bundle_image
              return false
            end
          end

          if File.file? "#{@web_image.build_path.shellescape}/package.json"
            unless yarn_install
              return false
            end
          end

          if @web_image.has_assets
            @web_image.update_attributes build_state: :building_assets
            unless build_assets
              return false
            end
          end

          @web_image.update_attributes build_state: :packaging
          unless package_build
            return false
          end

          @web_image.update_attributes build_state: :storing
          old_file_id = @web_image.file_id
          file = Mongoid::GridFs.put("#{@web_image.build_path}.tar.bz2")
          @web_image.update_attribute :file_id, file.id
          Mongoid::GridFs.delete old_file_id if old_file_id
        rescue Exception => e
          CloudModel.log_exception e
          @web_image.update_attributes build_state: :failed, build_last_issue: "#{e}"
        end

        @web_image.update_attributes build_state: :finished

        return true
      end

      def redeploy options={}
        unless @web_image.redeploy_state == :pending or options[:force]
          puts "Redeploy WebImage #{@web_image.name} failed, as it is not pending for redeploy: #{@web_image.redeploy_state}"
          return false
        end
        @web_image.update_attributes redeploy_state: :running, redeploy_last_issue: nil
        puts "Redeploy WebImage #{@web_image.name}"
        begin
          services = @web_image.services

          services.each do |service|
            if service.redeployable? or options[:force]
              service.update_attributes redeploy_web_image_state: :pending
            end
          end
          services.each do |service|
            service.redeploy! options
          end
        rescue Exception => e
          CloudModel.log_exception e
          @web_image.update_attributes redeploy_state: :failed, redeploy_last_issue: "#{e}"
          return false
        end
        @web_image.update_attributes redeploy_state: :finished
      end

      def run_within_build_env step, command
        orig_bundler_bin_path = ENV['BUNDLE_BIN_PATH']
        orig_rubyopt = ENV['RUBYOPT']

        # This works with Bundler 1.3.5; Perhaps it needs updating when Bundler version is other
        Bundler.with_original_env do
          ENV['GEM_PATH'] = ''
          ENV['GEM_HOME'] = @web_image.build_gem_home
          ENV['BUNDLE_BIN_PATH'] = orig_bundler_bin_path
          ENV['PATH'] = "#{@web_image.build_gem_home}/bin:#{ENV['PATH']}"
          ENV['RUBYOPT'] = orig_rubyopt

          run_step step, command
        end
      end

      def run_with_clean_env step, command
        # Bundler.with_clean_env do
        #   run_step step, command
        # end

        Bundler.with_original_env do
          ENV.delete_if { | k, _ | k[0, 7] == "BUNDLE_" }
          ENV["BUNDLE_GEMFILE"] = "#{@web_image.build_path}/Gemfile"
          ENV["PATH"] ||= "/usr/bin:/bin:/usr/sbin:/sbin"
          ENV["PATH"] += ':/usr/local/bin'
          ENV["GEM_PATH"] ||= ''
          ENV["GEM_PATH"] += ":/usr/local/lib/ruby/gems/#{Gem.ruby_api_version}:/usr/lib/ruby/gems/#{Gem.ruby_api_version}"
          ENV["RUBYLIB"] = nil
          if ENV.has_key?("RUBYOPT")
            ENV["RUBYOPT"] = ENV["RUBYOPT"].sub("-rbundler/setup", "")
          end

          # puts "----"
          # pp ENV
          # puts "----"
          # puts command
          # puts "----"
          # Rails.logger.debug ENV.to_json

          run_step step, command
        end
      end

      def run_step step, command
        Rails.logger.debug "### #{step}: #{command}"
        command = "PATH=/bin:#{ENV["PATH"].shellescape} #{command}"
        puts command
        c_out = `#{command}`
        unless $?.success?
          Rails.logger.error "Error running command:\n  #{command}\n  #{$?}\n#{c_out.lines.map{|l| "    #{l}"} * ""}\n#----"
          Rails.logger.error $?

          raise ExecutionException.new command, "#{step} failed (#{$?})", c_out
        end
        c_out
      end

    end
  end
end