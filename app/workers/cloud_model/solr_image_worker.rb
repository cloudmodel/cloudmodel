module CloudModel
  class SolrImageWorker < BaseWorker
    
    def initialize(solr_image)
      @solr_image = solr_image
    end
    
    def checkout_git        
      unless File.directory?(@solr_image.build_path)
        unless system "mkdir -p #{@solr_image.build_path.shellescape}"
          raise "Could not make checkout directory '#{@solr_image.build_path}'"
          return false
        end

        begin
          run_step "Cloning", "git clone #{@solr_image.git_server.shellescape}:#{@solr_image.git_repo.shellescape} #{@solr_image.build_path.shellescape}"
        rescue Exception => e
          CloudModel.log_exception e
          @solr_image.update_attributes build_state: :failed, build_last_issue: "Unable to clone repository '#{@solr_image.git_repo}'."
          system "rm -rf #{@solr_image.build_path.shellescape}"
          return false
        end
      end
      
      git_script = "cd #{@solr_image.build_path.shellescape} && "
      git_script += "git checkout #{@solr_image.git_branch.shellescape} &&"
      git_script += "git pull &&"
      git_script += "git submodule init &&"
      git_script += "git submodule update"
      
      begin 
        run_step "Pulling", git_script
      rescue CloudModel::ExecutionException => e
        CloudModel.log_exception e
        @solr_image.update_attributes build_state: :failed, build_last_issue: "Unable to checkout branch '#{@solr_image.git_branch}' on repository '#{@solr_image.git_repo}'."
        return false
      end
      
      begin
        @solr_image.update_attribute :git_commit, run_step("Get Git Commit", "cd #{@solr_image.build_path} && git log | head -1 | sed s/'commit '//")
      rescue Exception => e
        CloudModel.log_exception e
        @solr_image.update_attribute :git_commit,  "failed to get commit hash"
      end
            
      return true
    end
        
    def get_solr
      @solr_version = File.read("#{@solr_image.build_path}/SOLR_VERSION").strip
      solr_mirror = CloudModel::SolrMirror.find_or_create_by(version: @solr_version)
    end    
      
    def package_build
      begin
        run_step "Packaging", "/bin/tar -cpjf #{@solr_image.build_path.shellescape}-building.tar.bz2 --directory #{@solr_image.build_path.shellescape}/solr --exclude={'.git','./.gitignore','./.gitmodules','./tmp/**/*','./log/**/*','./spec','./features','.rspec','.gitkeep','./bundle/#{Bundler.ruby_scope}/cache','.bundle/#{Bundler.ruby_scope}/doc'} ."
      rescue CloudModel::ExecutionException => e
        CloudModel.log_exception e
        @solr_image.update_attributes build_state: :failed, build_last_issue: 'Unable to package image.'      
        return false
      end
      system "mv #{@solr_image.build_path.shellescape}-building.tar.bz2 #{@solr_image.build_path.shellescape}.tar.bz2"
      
      return true
    end
    
    def build options = {}
      return false unless @solr_image.build_state == :pending or options[:force]
      @solr_image.update_attributes build_state: :running, build_last_issue: nil    
       
      if options[:clean]
        system "rm -rf #{@solr_image.build_path.shellescape}"
      end
      
      begin 
        @solr_image.update_attributes build_state: :checking_out
        unless checkout_git
          return false
        end
        
        unless get_solr
          return false
        end
      
        @solr_image.update_attributes build_state: :packaging
        unless package_build
          return false
        end

        @solr_image.update_attributes build_state: :storing
        old_file_id = @solr_image.file_id
        file = Mongoid::GridFs.put("#{@solr_image.build_path}.tar.bz2")
        @solr_image.update_attributes file_id: file.id, solr_version: @solr_version
        Mongoid::GridFs.delete old_file_id if old_file_id
      rescue Exception => e
        CloudModel.log_exception e
        @solr_image.update_attributes build_state: :failed, build_last_issue: "#{e}"
        return false     
      end
      
      @solr_image.update_attributes build_state: :finished
  
      return true
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