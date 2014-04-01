module CloudModel
  def self.call_rake(task, options = {})
    options[:rails_env] ||= Rails.env
    args = options.map { |n, v| "#{n.to_s.upcase.shellescape}='#{v.to_s.shellescape}'" }
    bundle = 'bundle'
    bundle = 'PATH=/bin:/sbin:/usr/bin /usr/local/bin/bundle' unless Rails.env.test? or Rails.env.development?
  
    Rails.logger.info "CALL RAKE: #{bundle} exec rake #{task} #{args.join(' ')}"
  
    system "#{bundle} exec rake #{task.shellescape} #{args.join(' ')} --trace >>#{Rails.root}/log/#{Rails.env.to_s.shellescape}-rake.log 2>&1 &" 
  end
end