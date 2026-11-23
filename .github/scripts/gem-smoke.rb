# frozen_string_literal: true

# Installs a built zsv .gem into an empty GEM_HOME with `gem install --local`,
# then requires it from outside any checkout and parses a CSV string. Exits
# non-zero, naming the cause, when any of that fails.
#
#   ruby .github/scripts/gem-smoke.rb pkg/zsv-1.4.4.gem
#   ruby .github/scripts/gem-smoke.rb pkg/zsv-1.4.4-x86_64-linux-gnu.gem --precompiled
#
# --precompiled also asserts the gem carries a binary for this Ruby: installing
# it must compile nothing. ci.yml runs the source gem under `unshare -rn` (no
# network); native-gems.yml runs each platform gem on a matching runner.
require 'rbconfig'
require 'tmpdir'

gem_file = File.expand_path(ARGV.fetch(0) { abort 'usage: gem-smoke.rb ZSV_GEM_FILE [--precompiled]' })
precompiled = ARGV.include?('--precompiled')
abort "gem-smoke: no such file: #{gem_file}" unless File.file?(gem_file)

CHECK = <<~'RUBY'
  # realpath: on macOS the temp dir is /var/..., which Ruby records as /private/var/...
  home = File.join(File.realpath(ENV.fetch('GEM_HOME')), '')
  spec = Gem::Specification.find_by_name('zsv')
  if ENV['ZSV_SMOKE_PRECOMPILED'] == '1' && (spec.platform.to_s == 'ruby' || !spec.extensions.empty?)
    abort "expected a precompiled gem, got platform #{spec.platform} with extensions #{spec.extensions.inspect}"
  end

  require 'zsv'
  rows = ZSV.parse("a,b\n1,\"2,3\"\n")
  abort "ZSV.parse returned #{rows.inspect}" unless rows == [%w[a b], ['1', '2,3']]

  stray = $LOADED_FEATURES.grep(/zsv/).reject { |path| File.realpath(path).start_with?(home) }
  abort "zsv was loaded from outside the installed gem: #{stray.inspect}" unless stray.empty?

  puts "zsv #{ZSV::VERSION} (#{spec.platform}) installed and parses on #{RUBY_DESCRIPTION}"
RUBY

Dir.mktmpdir('zsv-gem-smoke') do |dir|
  home = File.join(dir, 'gems')
  env = { 'GEM_HOME' => home, 'GEM_PATH' => home, 'ZSV_SMOKE_PRECOMPILED' => precompiled ? '1' : '0' }
  # Gem.ruby -S gem: the gem command of the Ruby running this script.
  install = [Gem.ruby, '-S', 'gem', 'install', '--local', '--no-document', gem_file]
  unless system(env, *install)
    Dir.glob(File.join(home, 'extensions', '**', 'gem_make.out')).each { |log| warn File.read(log) }
    abort "gem-smoke: `gem install --local #{File.basename(gem_file)}` failed. A source gem must build " \
          'from files inside the gem (zsv.gemspec spec.files), with no network.'
  end
  # chdir into the temp dir so nothing resolves against the checkout.
  system(env, Gem.ruby, '-e', CHECK, chdir: dir) or abort 'gem-smoke: the installed gem did not load and parse'
end
