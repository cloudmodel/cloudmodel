# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV["RAILS_ENV"] ||= 'test'

# Coverage (opt-in): COVERAGE=1 bundle exec rspec
#
# Uses Ruby's VM-level Coverage library so Zeitwerk's lazy autoloads are
# captured (plain `deep-cover exec` misses them and reports 0%). deep-cover's
# builtin_takeover makes line coverage stricter: a line counts as covered only
# when *everything* on it ran. Must be required before any engine code loads.
if ENV['COVERAGE']
  begin
    require 'deep_cover/builtin_takeover'
  rescue LoadError
    # deep-cover is optional — fall back to plain builtin Coverage
  end
  require 'coverage'
  Coverage.start

  at_exit do
    root = File.expand_path('../..', __FILE__)
    results = Coverage.result.select do |path, _|
      (path.start_with?("#{root}/app/") || path.start_with?("#{root}/lib/")) &&
        !path.include?('/spec/')
    end

    files = results.map do |path, lines|
      relevant = lines.compact
      covered  = relevant.count { |hits| hits > 0 }
      total    = relevant.size
      { path: path.sub("#{root}/", ''), covered: covered, total: total,
        pct: total.zero? ? 100.0 : (covered.to_f / total * 100) }
    end

    total_lines   = files.sum { |f| f[:total] }
    covered_lines = files.sum { |f| f[:covered] }
    overall = total_lines.zero? ? 0.0 : (covered_lines.to_f / total_lines * 100)

    worst = files.select { |f| f[:total] > 0 }.sort_by { |f| f[:pct] }.first(15)

    puts "\n" + ('=' * 72)
    puts format('Coverage: %.2f%% (%d/%d lines) across %d files',
                overall, covered_lines, total_lines, files.size)
    puts '-' * 72
    puts 'Lowest-covered files:'
    worst.each do |f|
      puts format('  %6.2f%%  %4d/%-4d  %s', f[:pct], f[:covered], f[:total], f[:path])
    end
    puts '=' * 72
  end
end

require "rails/mongoid"
require File.expand_path("../dummy/config/environment", __FILE__)
require 'rspec/rails'
require 'mongoid-rspec'
require 'timecop'

# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.

Dir[Rails.root.join("../../spec/support/**/*.rb")].each { |f| require f }

require 'miniskirt'
Dir[Rails.root.join("../../spec/factories/**/*_factory.rb")].each {|f| require f}

RSpec.configure do |config|
  config.include Mongoid::Matchers
  
  config.before(:each) do
    Timecop.return
    Mongoid.purge!
    # CloudModel.log_exception writes the backtrace to stderr so humans see
    # failures in console/rake/production. Silence it here to keep spec output
    # clean; specs that assert on it can `and_call_original`.
    allow(CloudModel).to receive(:log_exception)
  end
  
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
  config.infer_base_class_for_anonymous_controllers = false
  #config.order = "random"
  
  config.include SshHelpers, type: :ssh  
end

RSpec::Mocks.configuration.allow_message_expectations_on_nil = true