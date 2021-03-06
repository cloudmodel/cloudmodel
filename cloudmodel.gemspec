$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "cloud_model/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "cloudmodel"
  s.version     = CloudModel::VERSION
  s.authors     = ["Sven G. Broenstrup (StarPeak)"]
  s.email       = ["info@cloud-model.org"]
  s.homepage    = "http://cloud-model.org/"
  s.licenses    = ['MIT']
  s.summary     = "Cloud admin with Ruby on Rails"
  s.description = "Ruby on Rails ActiveModel representation of common cloud admin tasks."

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  # s.test_files = Dir["spec/**/*"]

  s.add_dependency 'rails', '~> 6.0', '>= 6.0.3.2'
  s.add_dependency 'mongoid', '~> 7.0', '>= 7.1.2'
  s.add_dependency 'mongoid-grid_fs', '~> 2.3'

  s.add_dependency 'bcrypt-ruby', '~> 3.0', '>= 3.0.0'
  s.add_dependency 'netaddr', '~> 2.0', '>= 2.0.4'
  s.add_dependency 'net-sftp', '~> 2.1', '>= 2.1.0'
  s.add_dependency 'net-ping', '~> 2.0'

  # For service checks
  s.add_dependency 'redis'
  s.add_dependency 'mysql2'
end
