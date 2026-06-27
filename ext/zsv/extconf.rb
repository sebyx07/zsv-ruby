# frozen_string_literal: true

require 'mkmf'
require 'net/http'
require 'uri'
require 'fileutils'
require 'rubygems/package'
require 'zlib'
require 'openssl'

# ZSV version to compile against
ZSV_VERSION = '1.4.3' # zsv C library version (not gem version)
ZSV_URL = "https://github.com/liquidaty/zsv/archive/refs/tags/v#{ZSV_VERSION}.tar.gz".freeze
# Use absolute path relative to the original extconf.rb location
EXTCONF_DIR = File.expand_path(__dir__)
VENDOR_DIR = File.join(EXTCONF_DIR, 'vendor')
ZSV_DIR = File.join(VENDOR_DIR, "zsv-#{ZSV_VERSION}")

def download_file(url, destination, redirect_limit = 10, verify_ssl = true)
  abort('Too many redirects') if redirect_limit.zero?

  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)

  if uri.scheme == 'https'
    http.use_ssl = true
    http.verify_mode = verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    http.ca_file = ENV['SSL_CERT_FILE'] if ENV['SSL_CERT_FILE'] && verify_ssl
  end

  request = Net::HTTP::Get.new(uri.request_uri)

  begin
    response = http.request(request)
  rescue OpenSSL::SSL::SSLError => e
    if verify_ssl
      # Retry without SSL verification (GitHub is trusted)
      warn "SSL verification failed (#{e.message}), retrying without verification..."
      return download_file(url, destination, redirect_limit, false)
    end
    raise
  end

  case response
  when Net::HTTPRedirection
    download_file(response['location'], destination, redirect_limit - 1, verify_ssl)
  when Net::HTTPSuccess
    File.binwrite(destination, response.body)
  else
    abort("Failed to download: #{response.code} #{response.message}")
  end
end

def extract_tar_gz(tarball, destination)
  Gem::Package::TarReader.new(Zlib::GzipReader.open(tarball)) do |tar|
    tar.each do |entry|
      dest_path = File.join(destination, entry.full_name)

      if entry.directory?
        FileUtils.mkdir_p(dest_path)
      elsif entry.file?
        FileUtils.mkdir_p(File.dirname(dest_path))
        File.binwrite(dest_path, entry.read)
        FileUtils.chmod(entry.header.mode, dest_path)
      end
    end
  end
end

def download_and_extract_zsv
  return if File.directory?(ZSV_DIR)

  puts "Downloading zsv #{ZSV_VERSION}..."
  FileUtils.mkdir_p(VENDOR_DIR)

  tarball = File.join(VENDOR_DIR, 'zsv.tar.gz')
  download_file(ZSV_URL, tarball)

  puts 'Extracting zsv...'
  extract_tar_gz(tarball, VENDOR_DIR)
  FileUtils.rm_f(tarball)

  abort('zsv directory not found after extraction') unless File.directory?(ZSV_DIR)
  puts "zsv #{ZSV_VERSION} downloaded successfully"
end

def build_zsv
  puts 'Building zsv library...'

  # Build zsv static library
  Dir.chdir(ZSV_DIR) do
    # Configure zsv
    system('./configure') or abort('Failed to configure zsv') unless File.exist?('config.mk')

    # Build the library
    Dir.chdir('src') do
      system('make', 'build') or abort('Failed to build zsv library')
    end
  end

  puts 'zsv library built successfully'
end

# Download and build zsv
download_and_extract_zsv
build_zsv

# Determine build directory based on platform
platform_dir = if RUBY_PLATFORM =~ /darwin/
                 'Darwin'
               elsif RUBY_PLATFORM =~ /linux/
                 'Linux'
               else
                 'generic'
               end

# Find the built library - compiler name varies (gcc, gcc-14, clang, etc.)
# Search for libzsv.a in the build directory
build_rel_dir = File.join(ZSV_DIR, 'build', platform_dir, 'rel')
zsv_lib = Dir.glob(File.join(build_rel_dir, '*', 'lib', 'libzsv.a')).first

abort("libzsv.a not found in #{build_rel_dir}/*/lib/") unless zsv_lib && File.exist?(zsv_lib)

zsv_lib_dir = File.dirname(zsv_lib)

# Add zsv include path
include_dir = File.join(ZSV_DIR, 'include')

# Add compiler and linker flags
$INCFLAGS << " -I#{include_dir}"
$CFLAGS << ' -std=c99 -Wall -Wextra'
$CFLAGS << ' -O3' # Optimization level

# Configure include and lib paths
dir_config('zsv', include_dir, zsv_lib_dir)

# Find zsv header
abort("zsv.h not found in #{include_dir}") unless have_header('zsv.h')

# Link the static library
$LOCAL_LIBS << " #{zsv_lib}"

# Platform-specific adjustments
if RUBY_PLATFORM =~ /darwin/
  $LDFLAGS << ' -framework Foundation'
elsif RUBY_PLATFORM =~ /linux/
  $LIBS << ' -lpthread -lm'
end

# Check for Ruby 3.2+ hash capacity preallocation
have_func('rb_hash_new_capa')

# Create Makefile
create_makefile('zsv/zsv')
