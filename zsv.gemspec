# frozen_string_literal: true

require_relative 'lib/zsv/version'

Gem::Specification.new do |spec|
  spec.name = 'zsv'
  spec.version = ZSV::VERSION
  spec.authors = ['sebyx07']
  spec.email = ['gore.sebyx@yahoo.com']

  spec.summary = 'SIMD-accelerated CSV parser using zsv'
  spec.description = "A drop-in replacement for Ruby's CSV stdlib that uses zsv " \
                     '(SIMD-accelerated C library) for 5-6x faster CSV parsing. ' \
                     'Supports both MRI (via C extension) and JRuby (via Java/JNI).'
  spec.homepage = 'https://github.com/sebyx07/zsv-ruby'
  spec.license = 'MIT'

  # Support both MRI Ruby 3.3+ and JRuby 9.4+
  # JRuby 9.4 targets Ruby 3.1, so we lower the requirement
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir[
    'lib/**/*.rb',
    'ext/**/*.{c,h,rb,java}',
    'LICENSE*',
    'README.md',
    'CHANGELOG.md'
  ]

  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Platform-specific extensions
  spec.extensions = if RUBY_PLATFORM == 'java'
                      ['ext/zsv/java/extconf.rb']
                    else
                      ['ext/zsv/extconf.rb']
                    end

  # Development dependencies
  spec.add_development_dependency 'benchmark-ips', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
