# frozen_string_literal: true

require_relative 'lib/zsv/version'

Gem::Specification.new do |spec|
  spec.name = 'zsv'
  spec.version = ZSV::VERSION
  spec.authors = ['sebyx07']
  spec.email = ['gore.sebyx@yahoo.com']

  spec.summary = 'SIMD-accelerated CSV parser wrapping the zsv C library'
  spec.description = "A CSV parser with the reading API of Ruby's CSV stdlib, implemented as a C " \
                     'extension over zsv (SIMD-accelerated). Typically several times faster than CSV.'
  spec.homepage = 'https://github.com/sebyx07/zsv-ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'
  # gem X.Y.Z wraps zsv X.Y.Z; gem-only fixes add a fourth segment (X.Y.Z.N).
  spec.metadata['zsv_version'] = File.read(File.expand_path('ext/zsv/ZSV_UPSTREAM', __dir__))[/^version=(.+)$/, 1]
  spec.metadata['zsv_source_uri'] = 'https://github.com/liquidaty/zsv'
  spec.metadata['zsv_license'] = 'MIT' # ext/zsv/vendor/zsv/LICENSE

  # The vendored zsv source ships in the gem, so installing needs no network.
  spec.files = Dir[
    'lib/**/*.rb',
    'ext/zsv/*.{c,h,rb}',
    'ext/zsv/ZSV_UPSTREAM',
    'ext/zsv/vendor/zsv/**/*',
    'LICENSE*',
    'README.md',
    'CHANGELOG.md'
  ].select { |path| File.file?(path) }

  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.extensions = ['ext/zsv/extconf.rb']

  # Development dependencies
  spec.add_development_dependency 'benchmark-ips', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rake-compiler', '~> 1.3'
  spec.add_development_dependency 'rake-compiler-dock', '~> 1.12'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
