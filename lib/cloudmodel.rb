require 'mongoid-grid_fs'
require "cloud_model/config"
require "cloud_model/engine"
require "cloud_model/call_rake"
require "cloud_model/enum_fields"
require "cloud_model/accept_size_strings"
require "cloud_model/used_in_guests_as"
require "cloud_model/backup_tools"
require "cloud_model/model_has_issues"
require "cloud_model/smart_to_string"

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
  
  class ExecutionException < Exception
    attr_accessor :command, :error, :output
    def initialize(command, error, output)
      @command = command
      @error = error
      @output = output
    end
  end
end