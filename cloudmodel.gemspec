require_relative "lib/cloud_model/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name        = "cloudmodel"
  spec.version     = CloudModel::VERSION
  spec.authors     = ["Sven G. Brönstrup (StarPeak)"]
  spec.email       = ["info@cloud-model.org"]
  spec.homepage    = "http://cloud-model.org/"
  spec.summary     = "Cloud admin with Ruby on Rails"
  spec.description = "Ruby on Rails ActiveModel representation of common cloud admin tasks."
  spec.license     = 'MIT'


  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/cloudmodel/cloudmodel"
  spec.metadata["changelog_uri"] = "https://github.com/cloudmodel/cloudmodel/commits/master"


  spec.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  spec.add_dependency 'rails', '~> 6.0', '>= 6.0.3'
  spec.add_dependency 'mongoid', '~> 7.0', '>= 7.1.2'
  spec.add_dependency 'mongoid-grid_fs', '~> 2.3'

  spec.add_dependency 'bcrypt-ruby', '~> 3.0', '>= 3.0.0'
  spec.add_dependency 'netaddr', '~> 2.0', '>= 2.0.4'
  spec.add_dependency 'net-sftp', '~> 2.1', '>= 2.1.0'
  spec.add_dependency 'net-ping', '~> 2.0'

  # For service checks
  spec.add_dependency 'redis'
  spec.add_dependency 'mysql2'
end
