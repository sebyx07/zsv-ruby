# frozen_string_literal: true

# JRuby JNI extension builder
# This script downloads zsv, compiles it, and builds the JNI wrapper

require 'fileutils'
require 'net/http'
require 'uri'
require 'rbconfig'

ZSV_VERSION = '1.3.0'
ZSV_URL = "https://github.com/liquidaty/zsv/archive/refs/tags/v#{ZSV_VERSION}.tar.gz"

def run(cmd)
  puts ">> #{cmd}"
  system(cmd) || abort("Command failed: #{cmd}")
end

def download_zsv(dest_dir)
  tarball = File.join(dest_dir, "zsv-#{ZSV_VERSION}.tar.gz")

  unless File.exist?(tarball)
    puts "Downloading zsv #{ZSV_VERSION}..."
    uri = URI(ZSV_URL)
    
    # Follow redirects
    loop do
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      request = Net::HTTP::Get.new(uri)
      response = http.request(request)
      
      case response
      when Net::HTTPRedirection
        uri = URI(response['location'])
      when Net::HTTPSuccess
        File.open(tarball, 'wb') { |f| f.write(response.body) }
        break
      else
        abort("Failed to download zsv: #{response.code}")
      end
    end
  end

  tarball
end

# Paths
ext_dir = File.dirname(File.expand_path(__FILE__))
vendor_dir = File.join(ext_dir, '..', 'vendor')
zsv_dir = File.join(vendor_dir, "zsv-#{ZSV_VERSION}")
lib_dir = File.expand_path('../../../lib/zsv/java', ext_dir)

FileUtils.mkdir_p(vendor_dir)
FileUtils.mkdir_p(lib_dir)
FileUtils.mkdir_p(File.join(lib_dir, 'classes'))

# Download and extract zsv if needed
unless File.directory?(zsv_dir)
  tarball = download_zsv(vendor_dir)
  Dir.chdir(vendor_dir) { run("tar xzf #{File.basename(tarball)}") }
end

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
