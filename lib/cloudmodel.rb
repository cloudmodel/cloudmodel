require 'mongoid-grid_fs'
require "cloud_model/config"
require "cloud_model/engine"
require "cloud_model/call_rake"
require "cloud_model/execution_exception"

module CloudModel  
  def self.config
    @config ||= CloudModel::Config.new
  end
  
  def self.configure(&block)
    config.configure(&block)
  end

  def self.log_exception e
    Rails.logger.error "CloudModel: uncaught #{e.class} exception while handling connection: #{e.message}"
    Rails.logger.error "Stack trace:\n#{e.backtrace.map {|l| "  #{l}\n"}.join}"
  end
end