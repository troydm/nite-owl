
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "nite/owl/version"

Gem::Specification.new do |spec|
  spec.name          = "nite-owl"
  spec.version       = Nite::Owl::VERSION
  spec.authors       = ["Dmitry Geurkov"]
  spec.email         = ["d.geurkov@gmail.com"]

  spec.summary       = %q{Linux/OSX File System Events Watcher.}
  spec.description   = %q{Linux/OSX File System Events Watcher with minimal dependencies and simple Ruby DSL based configuration.}
  spec.homepage      = "https://github.com/troydm/nite-owl"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rb-fsevent", "~> 0.10", ">= 0.10.2"
  spec.add_dependency "rb-inotify", "~> 0.9", ">= 0.9.10"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 12.3.3"
  spec.add_development_dependency "rspec", "~> 3.0"
end
