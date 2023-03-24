source 'https://rubygems.org'

# Specify your gem's dependencies in redis_cluster.gemspec
gemspec

group :development do
  gem 'appraisal'

  platforms :mri do
    if RUBY_VERSION >= "2.0.0"
      gem "pry-byebug"
    end
  end
end
