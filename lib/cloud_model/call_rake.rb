module CloudModel
  def self.call_rake(task, options = {})
    options[:rails_env] ||= Rails.env
    args = options.map { |n, v| "#{n.to_s.upcase.shellescape}='#{v.to_s.shellescape}'" }
  
    Rails.logger.debug "CALL RAKE: #{CloudModel.config.bundle_command} exec rake #{task} #{args.join(' ')}"
  
    system "#{CloudModel.config.bundle_command} exec rake #{task.shellescape} #{args.join(' ')} --trace >>#{Rails.root}/log/#{Rails.env.to_s.shellescape}-rake.log 2>&1 &" 
  end
end