# frozen_string_literal: true

# JRuby JNI extension builder
# This script downloads zsv, compiles it, and builds the JNI wrapper

require 'fileutils'
require 'net/http'
require 'uri'
require 'rbconfig'
require 'rubygems/package'
require 'zlib'
require 'openssl'

ZSV_VERSION = '1.3.0'
ZSV_URL = "https://github.com/liquidaty/zsv/archive/refs/tags/v#{ZSV_VERSION}.tar.gz"

def run(cmd)
  puts ">> #{cmd}"
  system(cmd) || abort("Command failed: #{cmd}")
end

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

def download_and_extract_zsv(vendor_dir, zsv_dir)
  # Check if configure script exists (indicates proper extraction)
  configure_path = File.join(zsv_dir, 'configure')
  return if File.exist?(configure_path) && File.executable?(configure_path)

  # Remove incomplete extraction
  FileUtils.rm_rf(zsv_dir) if File.directory?(zsv_dir)

  puts "Downloading zsv #{ZSV_VERSION}..."
  FileUtils.mkdir_p(vendor_dir)

  tarball = File.join(vendor_dir, 'zsv.tar.gz')
  download_file(ZSV_URL, tarball)

  puts 'Extracting zsv...'
  extract_tar_gz(tarball, vendor_dir)
  FileUtils.rm_f(tarball)

  abort('zsv directory not found after extraction') unless File.directory?(zsv_dir)
  puts "zsv #{ZSV_VERSION} downloaded successfully"
end

# Paths
ext_dir = File.dirname(File.expand_path(__FILE__))
vendor_dir = File.join(ext_dir, '..', 'vendor')
zsv_dir = File.join(vendor_dir, "zsv-#{ZSV_VERSION}")
lib_dir = File.expand_path('../../../lib/zsv/java', ext_dir)

FileUtils.mkdir_p(vendor_dir)
FileUtils.mkdir_p(lib_dir)
FileUtils.mkdir_p(File.join(lib_dir, 'classes'))

# Download and extract zsv (downloads fresh if configure doesn't exist)
download_and_extract_zsv(vendor_dir, zsv_dir)

# Build zsv
Dir.chdir(zsv_dir) do
  run('./configure') unless File.exist?('config.mk')
  run('make -C src build')
end

# Find zsv library
os = RbConfig::CONFIG['host_os']
arch = RbConfig::CONFIG['host_cpu']

# zsv build directory varies by platform and compiler
# Look for the library in possible locations
zsv_lib = nil
lib_search_paths = case os
                   when /darwin/i
                     # macOS: try various build paths (gcc version varies)
                     Dir.glob(File.join(zsv_dir, 'build/Darwin*/rel/*/lib/libzsv.a'))
                   when /linux/i
                     Dir.glob(File.join(zsv_dir, 'build/Linux/rel/*/lib/libzsv.a'))
                   else
                     abort("Unsupported OS: #{os}")
                   end

zsv_lib = lib_search_paths.first
abort("zsv library not found. Searched: #{lib_search_paths.inspect}") unless zsv_lib && File.exist?(zsv_lib)
puts "Found zsv library at: #{zsv_lib}"

# Find Java
java_home = ENV['JAVA_HOME']
if java_home.nil? || java_home.empty?
  # Try common locations
  candidates = %w[
    /usr/lib/jvm/default-java
    /usr/lib/jvm/java-21-openjdk-amd64
    /usr/lib/jvm/java-17-openjdk-amd64
  ]
  java_home = candidates.find { |p| File.directory?(p) }
end
abort('JAVA_HOME not set and Java not found') unless java_home

java_include = File.join(java_home, 'include')
abort("Java include directory not found: #{java_include}") unless File.directory?(java_include)

java_include_os = case os
                  when /darwin/i then File.join(java_include, 'darwin')
                  when /linux/i then File.join(java_include, 'linux')
                  else abort("Unsupported OS: #{os}")
                  end

# Compile Java classes
puts 'Compiling Java classes...'
java_src = File.join(ext_dir, 'src', 'zsv')
classes_dir = File.join(lib_dir, 'classes')
run("javac -d #{classes_dir} #{java_src}/*.java")

# Compile JNI wrapper
puts 'Compiling JNI wrapper...'
jni_src = File.join(ext_dir, 'zsv_jni.c')
zsv_include = File.join(zsv_dir, 'include')

lib_ext = os =~ /darwin/i ? 'dylib' : 'so'
lib_name = "libzsv_jni.#{lib_ext}"
lib_path = File.join(lib_dir, lib_name)

cc_flags = [
  '-shared', '-fPIC', '-O3',
  "-I#{java_include}",
  "-I#{java_include_os}",
  "-I#{zsv_include}",
  "-I#{ext_dir}"
]

run("gcc #{cc_flags.join(' ')} -o #{lib_path} #{jni_src} #{zsv_lib}")

puts "Built #{lib_path}"
puts 'JRuby JNI extension built successfully!'

# Create dummy Makefile (required by RubyGems)
File.write(File.join(ext_dir, 'Makefile'), "all:\n\techo 'JNI extension already built'\n\ninstall:\n\techo 'Nothing to install'\n")
