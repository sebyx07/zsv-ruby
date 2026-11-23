# frozen_string_literal: true

require 'mkmf'
require 'fileutils'
require 'shellwords'
require_relative 'upstream'

# Builds the zsv C library from the source vendored in ext/zsv/vendor/zsv (see
# ZSV_UPSTREAM and `rake zsv:vendor`), then links it statically into the
# extension. No network access happens here.
#
# The default build targets the baseline CPU of the architecture (SSE2 on
# x86_64, NEON on aarch64), so a binary built on one machine (a Docker image
# built in CI, say) runs on any other machine of that architecture instead of
# dying with SIGILL.
#
# Options (`gem install zsv -- --enable-native`, or ZSV_NATIVE=1):
#   --enable-native       build for the build machine's CPU (-march=native,
#                         AVX2 when it has it). Only for binaries that run
#                         where they were built.
#   --enable-cross-build  set by the Rakefile for rake-compiler-dock builds of
#                         precompiled gems; always baseline, ignores
#                         --enable-native.

def vendored_zsv_dir
  unless ZSVUpstream.vendored_current?
    abort <<~MSG
      The zsv #{ZSVUpstream.version} C source is missing from #{ZSVUpstream::VENDOR_DIR}
      (or was vendored from a different ZSV_UPSTREAM pin).
      In a git checkout run `bundle exec rake zsv:vendor`; released gems always include it.
    MSG
  end
  ZSVUpstream::VENDOR_DIR
end

def cross_compiling?
  enable_config('cross-build', false)
end

def native_build?
  !cross_compiling? && enable_config('native', ENV['ZSV_NATIVE'] == '1')
end

def configure_args
  # --minimal drops ZSV_EXTRAS (row limits, progress callbacks, sidecar
  # overwrite files), which this gem does not use and which needs sqlite3.h
  # from upstream's app/ tree, deliberately not vendored.
  args = %w[--minimal=yes]
  # SSE2 (x86_64) and NEON (aarch64) are part of the baseline ABI and still
  # select zsv's SIMD scanner; only AVX/AVX2 and -march=native are dropped.
  args += %w[--arch=none --force-avx2=no --force-avx=no] unless native_build?
  args
end

def build_env
  env = { 'CC' => RbConfig::CONFIG['CC'], 'AR' => RbConfig::CONFIG['AR'] }
  env['CROSS_COMPILING'] = 'yes' if cross_compiling?
  env.compact
end

def run!(env, *cmd)
  puts "#{env.map { |k, v| "#{k}=#{v.shellescape}" }.join(' ')} #{cmd.shelljoin}"
  system(env, *cmd) or abort("zsv build failed: #{cmd.shelljoin}")
end

# Builds a private copy so the vendored tree stays pristine and builds for
# several Rubies or platforms never share a config.mk.
def build_zsv(source_dir, build_dir)
  FileUtils.rm_rf(build_dir)
  FileUtils.cp_r(source_dir, build_dir)
  env = build_env
  Dir.chdir(build_dir) do
    run!(env, './configure', *configure_args)
    run!(env, find_executable('gmake') || 'make', '-C', 'src', 'build', "VERSION=#{ZSVUpstream.version}")
  end
  Dir.glob(File.join(build_dir, 'build', '*', 'rel', '*', 'lib', 'libzsv.a')).first or
    abort("libzsv.a not found under #{build_dir}/build")
end

zsv_build_dir = File.join(Dir.pwd, 'zsv-build')
puts "Building zsv #{ZSVUpstream.version} (#{native_build? ? 'native CPU' : 'portable baseline CPU'})"
zsv_lib = build_zsv(vendored_zsv_dir, zsv_build_dir)
include_dir = File.join(zsv_build_dir, 'include')

$INCFLAGS << " -I#{include_dir}"
$CFLAGS << ' -std=c99 -Wall -Wextra'
$CFLAGS << ' -O3'

abort("zsv.h not found in #{include_dir}") unless have_header('zsv.h')

$LOCAL_LIBS << " #{zsv_lib}"

if RUBY_PLATFORM.include?('darwin')
  $LDFLAGS << ' -framework Foundation'
elsif RUBY_PLATFORM.include?('linux')
  $LIBS << ' -lpthread -lm'
end

# Ruby 3.2+ hash capacity preallocation
have_func('rb_hash_new_capa')

create_makefile('zsv/zsv')
