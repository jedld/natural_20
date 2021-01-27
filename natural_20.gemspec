require_relative "lib/natural_20/version"

Gem::Specification.new do |spec|
  spec.name = "natural_20"
  spec.version = Natural20::VERSION
  spec.authors = ["Joseph Dayo"]
  spec.email = ["joseph.dayo@gmail.com"]

  spec.summary = %q{A ruby based engine for building text based RPGs based on DnD 5th Edition rules}
  spec.description = %q{A ruby based engine for building text based RPGs based on DnD 5th Edition rules}
  spec.homepage = "https://github.com/jedld/natural_20.git"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jedld/natural_20.git"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path("..", __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "solargraph"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-rspec"
  spec.add_development_dependency "rubocop-rake"
  spec.add_dependency "tty-table"
  spec.add_dependency "tty-prompt"
  spec.add_dependency "activesupport"
  spec.add_dependency "random_name_generator"
  spec.add_dependency "colorize"
  spec.add_dependency "pqueue"
  spec.add_dependency "i18n"
  spec.add_dependency "bond"
  if RUBY_ENGINE == "ruby"
    spec.add_dependency "pry-byebug"
  end
end
