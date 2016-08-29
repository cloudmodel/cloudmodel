module CloudModel
  class WebImageWorker < BaseWorker
    
    def initialize(web_image)
      @web_image = web_image
    end
    
    def checkout_git        
      unless File.directory?(@web_image.build_path)
        unless system "mkdir -p #{@web_image.build_path.shellescape}"
          raise "Could not make checkout directory '#{@web_image.build_path}'"
          return false
        end

        begin
          run_with_clean_env "Cloning", "git clone #{@web_image.git_server.shellescape}:#{@web_image.git_repo.shellescape} #{@web_image.build_path.shellescape}"
        rescue Exception => e
          CloudModel.log_exception e
          @web_image.update_attributes build_state: :failed, build_last_issue: "Unable to clone repository '#{@web_image.git_repo}'."
          system "rm -rf #{@web_image.build_path.shellescape}"
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
        run_with_clean_env "Bundling", "cd #{@web_image.build_path.shellescape} && #{CloudModel.config.bundle_command} install --gemfile #{@web_image.build_path.shellescape}/Gemfile --path ./bundle --deployment --without development test"
      rescue CloudModel::ExecutionException => e
        CloudModel.log_exception e
        @web_image.update_attributes build_state: :failed, build_last_issue: 'Unable to build image.'      
        system "rm -rf #{@web_image.build_gem_home.shellescape}"       
        return false
      end
      
      return true
    end
    
    def build_assets
      begin
        system "rm -rf #{@web_image.build_path.shellescape}/public/assets"
        
        run_with_clean_env "Building Assets", "cd #{@web_image.build_path.shellescape} && #{CloudModel.config.bundle_command} exec rake RAILS_ENV=production RAILS_GROUPS=assets assets:precompile"
      rescue CloudModel::ExecutionException => e
        CloudModel.log_exception e
        @web_image.update_attributes build_state: :failed, build_last_issue: 'Unable to build assets.'      
        system "rm -rf #{@web_image.build_path}/public/assets"
        return false
      end
      
      return true
    end
    
    def package_build
      begin
        run_within_build_env "Packaging", "tar -cpjf #{@web_image.build_path.shellescape}-building.tar.bz2 --directory #{@web_image.build_path.shellescape} --exclude={'.git','./.gitignore','./tmp/**/*','./log/**/*','./spec','./features','.rspec','.gitkeep','./bundle/#{Bundler.ruby_scope}/cache','.bundle/#{Bundler.ruby_scope}/doc'} ."
      rescue CloudModel::ExecutionException => e
        CloudModel.log_exception e
        @web_image.update_attributes build_state: :failed, build_last_issue: 'Unable to package image.'      
        return false
      end
      system "mv #{@web_image.build_path.shellescape}-building.tar.bz2 #{@web_image.build_path.shellescape}.tar.bz2"
      
      return true
    end
    
    def build options = {}
      return false unless @web_image.build_state == :pending or options[:force]
      @web_image.update_attributes build_state: :running, build_last_issue: nil    
       
      if options[:clean]
        system "rm -rf #{@web_image.build_path.shellescape}"
      end
      
      begin 
        @web_image.update_attributes build_state: :checking_out
        unless checkout_git
          return false
        end
        
        @web_image.update_attributes build_state: :bundling
        unless bundle_image
          return false
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
        ENV["PATH"] += ':/usr/local/bin'
        ENV["GEM_PATH"] ||= ''
        ENV["GEM_PATH"] += ":/usr/local/lib/ruby/gems/#{Gem.ruby_api_version}:/usr/lib/ruby/gems/#{Gem.ruby_api_version}"
        ENV["RUBYLIB"] = nil
        if ENV.has_key?("RUBYOPT")
          ENV["RUBYOPT"] = ENV["RUBYOPT"].sub("-rbundler/setup", "")
        end
        
        #puts "----"
        #puts command
        #puts "----"
        #puts ENV.to_json
        
        run_step step, command
      end
    end
      
    def run_step step, command      
      Rails.logger.debug "### #{step}: #{command}"
      c_out = `#{command}`
      unless $?.success?
        Rails.logger.error "Error running command:\n  #{command}\n  #{$?}\n#{c_out.lines.map{|l| "    #{l}"} * ""}\n#----"
        
        raise ExecutionException.new command, "#{step} failed (#{$?})", c_out
      end
      c_out
    end
    
  end
end