# -*- encoding: utf-8 -*-
require File.expand_path('../lib/bananasplit/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Glenn Gillen"]
  gem.email         = ["me@glenngillen.com"]
  gem.description   = %q{A split testing framework for Rack apps}
  gem.summary       = %q{Split testing framework for ruby/rack application}
  gem.homepage      = "https://github.com/glenngillen/bananasplit"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "bananasplit"
  gem.require_paths = ["lib"]
  gem.version       = BananaSplit::VERSION

  gem.add_development_dependency "rake", "0.8.7"
end
