source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Specify your gem's dependencies in cloudmodel-api-desec.gemspec.
gemspec

group :test do
  gem "rspec-rails"
  gem "mongoid-rspec"
  gem "fuubar"
  gem "timecop"
  gem 'miniskirt'
  gem 'faker'
  gem 'deep-cover', require: false
end

group :development, :test do
  gem "listen"
  gem "pry"
  gem 'yard'

  if true
    gem 'yard-mongoid', git: 'https://github.com/cloudmodel/yard-mongoid.git'
  else
    gem 'yard-mongoid', path: '../yard-mongoid'
  end
end