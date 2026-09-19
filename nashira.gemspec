# frozen_string_literal: true

require_relative "lib/nashira/version"

Gem::Specification.new do |spec|
  spec.name = "nashira"
  spec.version = Nashira::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "CI report cards for GitHub summaries and pull requests"
  spec.description = "Parse test, coverage, and benchmark reports into deterministic PNG and Markdown summaries."
  spec.homepage = "https://github.com/noxdea/nashira"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  files = Dir.chdir(__dir__) { Dir["**/*"].select { |file| File.file?(file) } } if files.empty?
  spec.files = files.reject do |file|
    file == gemspec || file.start_with?(*%w[Gemfile .gitignore .rspec spec/ .github/])
  end
  spec.bindir = "exe"
  spec.executables = ["nashira"]
  spec.require_paths = ["lib"]

  spec.add_dependency "zaniah", ">= 0.6.0", "< 0.7"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
