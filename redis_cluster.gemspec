# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'redis_cluster/version'

Gem::Specification.new do |spec|
  spec.name          = "redis_cluster"
  spec.version       = RedisCluster::VERSION
  spec.authors       = ["wangzc"]
  spec.email         = ["zhchsf@gmail.com"]

  spec.summary       = %q{redis cluster client}
  spec.description   = %q{redis cluster client}
  spec.homepage      = "http://www.iruby.com.cn"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  spec.metadata = {
    'allowed_push_host' => "https://gem.fury.io/invoca"
  }

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "redis", ">= 3.2", "<= 4.5.1"
  spec.add_dependency "hiredis", "~> 0.6"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "pry"
end
