# -*- encoding: utf-8 -*-
require File.expand_path('../lib/abingo/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Glenn Gillen"]
  gem.email         = ["me@glenngillen.com"]
  gem.description   = %q{A split testing framework for Rails 3.x.x}
  gem.summary       = %q{The ABingo split testing framework for Rails 3.x.x from Patrick McKenzie}
  gem.homepage      = "https://github.com/glenngillen/abingo"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "abingo"
  gem.require_paths = ["lib"]
  gem.version       = Abingo::VERSION

  gem.add_dependency "rails", "~> 3.0"
end
