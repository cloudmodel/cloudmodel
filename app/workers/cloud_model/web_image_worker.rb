module CloudModel
  class WebImageWorker < BaseWorker
    
    def initialize(web_image)
      @web_image = web_image
    end
    
    def checkout_git  
      unless File.directory?(build_path)
        unless system "mkdir -p #{@web_image.build_path}"
          raise "Could not make checkout directory '#{@web_image.build_path}'"
          return false
        end

        begin
          run_with_clean_env "Cloning", "git clone #{@web_image.git_server}:#{@web_image.git_repo} #{@web_image.build_path}/current"
        rescue Exception => e
          errors.add :git_repo, :repo_not_found
          system "rm -rf #{@web_image.build_path}/current"
          return false
        end
      end
      
      git_script = "cd #{@web_image.build_path}/current && "
      git_script += "git checkout #{@web_image.git_branch} &&"
      git_script += "git pull"
      
      begin 
        run_with_clean_env "Pulling", git_script
      rescue ExecutionException => e
        errors.add :git_branch, :branch_not_pulled
        return false
      end
      
      begin
        self.git_commit = run_with_clean_env "Get Version", "cd #{@web_image.build_path}/current && git log | head -1 | sed s/'commit '//"
      rescue
        self.git_commit = "failed to get commit hash"
      end
      
      return true
    end
    
    def bundle_image
      begin
        run_with_clean_env "Bundling", "cd #{@web_image.build_path}/current && bundle install --gemfile #{@web_image.build_path}/current/Gemfile --path ../shared/bundle --deployment --without development test"
      rescue ExecutionException => e
        errors.add :base, :bundle_failed
        system "rm -rf #{@web_image.build_gem_home}"
        
        return false
      end
      
      return true
    end
    
    def build_assets
      begin
        system "rm -rf #{build_path}/current/public/assets"
      
        run_within_build_env "Building Assets", "cd #{@web_image.build_path}/current && bundle exec rake RAILS_ENV=production RAILS_GROUPS=assets assets:precompile"
      rescue ExecutionException => e
        errors.add :has_assets, :building_assets_failed
        system "rm -rf #{@web_image.build_path}/current/public/assets"
        return false
      end
      
      return true
    end
    
    def package_build
      begin
        run_within_build_env "Packaging", "tar -cpjf #{@web_image.build_path}-building.tar.bz2 --directory #{@web_image.build_path} --exclude={'.git','./current/.gitignore','./current/tmp/**/*','./current/log/**/*','./spec','./features','.rspec','.gitkeep','./shared/bundle/#{Bundler.ruby_scope}/cache','./shared/bundle/#{Bundler.ruby_scope}/doc'} ."
      rescue ExecutionException => e
        errors.add :base, :packaging_failed
        return false
      end
      system "mv #{@web_image.build_path}-building.tar.bz2 #{@web_image.build_path}.tar.bz2"
      
      return true
    end
    
    def build
      unless checkout_git
        return false
      end
      
      unless bundle_image
        return false
      end

      if has_assets 
        unless build_assets
          return false
        end
      end
      
      unless package_build
        return false
      end

      old_file_id = file_id
      file = Mongoid::GridFs.put("#{@web_image.build_path}.tar.bz2")
      self.file_id = file.id
      Mongoid::GridFs.delete old_file_id if old_file_id
  
      return true
    end
    
    private
    def run_within_build_env step, command      
      orig_bundler_bin_path = ENV['BUNDLE_BIN_PATH']
      orig_rubyopt = ENV['RUBYOPT']
      
      # This works with Bundler 1.3.5; Perhaps it needs updating when Bundler version is other
      Bundler.with_original_env do
        ENV['GEM_PATH'] = ''
        ENV['GEM_HOME'] = @web_image.build_gem_home
        ENV['BUNDLE_BIN_PATH'] = orig_bundler_bin_path
        ENV['PATH'] = "#{build_gem_home}/bin:/bin:/usr/bin:/usr/local/bin"
        ENV['BUNDLE_GEMFILE'] = @web_image.build_gemfile
        ENV['RUBYOPT'] = orig_rubyopt
      
        run_step step, command
      end
    end
    
    def run_with_clean_env step, command
      Bundler.with_clean_env do
        run_step step, command
      end
    end
      
    def run_step step, command      
      Rails.logger.debug "### #{step}: #{command}"
      c_out = `#{command}`
      unless $?.success?
        Rails.logger.error "Error running command:\n  #{command}\n  #{$?}\n#{c_out.lines.map{|l| "    #{l}"} * ""}"
        
        raise ExecutionException.new command, "#{step} failed (#{$?})", c_out
      end
      c_out
    end
  end
end