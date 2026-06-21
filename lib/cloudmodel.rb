require 'mongoid-grid_fs'
require "cloud_model/config"
require "cloud_model/engine"
require "cloud_model/monitoring"
#require "cloud_model/call_rake"
require "cloud_model/execution_exception"

module CloudModel
  def self.config
    @config ||= CloudModel::Config.new
  end

  def self.configure(&block)
    config.configure(&block)
  end

  def self.log_exception e
    message = "CloudModel: uncaught #{e.class} exception while handling connection: #{e.message}"
    trace = "Stack trace:\n#{e.backtrace.to_a.map {|l| "  #{l}\n"}.join}"

    Rails.logger.error message
    Rails.logger.error trace

    # Also surface the exception and backtrace on stderr so a human running a
    # console, rake task, or production process sees what failed directly,
    # not only buried in the log. Tests silence this via a global stub in
    # spec_helper to keep spec output clean.
    warn message
    warn trace
  end

  def self.debian_names
    {
      'ubuntu-18.04' => 'Bionic Beaver',
      'ubuntu-20.04' => 'Focal Fossa',
      'ubuntu-22.04' => 'Jammy Jellyfish',
      'ubuntu-24.04' => 'Noble Numbat',
      'debian-11'    => 'Bullseye',
      'debian-12'    => 'Bookworm',
      'debian-13'    => 'Trixie',
      'debian-14'    => 'Forky'
    }
  end

  def self.debian_name version
    debian_names[version.match(/\A.*-[0-9]+(.[0-9]+)?/)[0]]
  end

  def self.debian_short_name version
    debian_name(version).split.first.downcase
  end
end