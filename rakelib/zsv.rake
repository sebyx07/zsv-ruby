# frozen_string_literal: true

# Vendoring of the upstream zsv C library into ext/zsv/vendor/zsv.
#
# The gem ships the vendored source so `gem install` needs no network and
# always builds the exact, checksum-verified release named in ZSV_UPSTREAM.

require 'digest'
require 'fileutils'
require 'net/http'
require 'rubygems/package'
require 'stringio'
require 'tmpdir'
require 'zlib'
require_relative '../ext/zsv/upstream'

module ZSVVendor
  MAX_REDIRECTS = 5

  module_function

  def download(url, redirects_left = MAX_REDIRECTS)
    raise "Too many redirects fetching #{url}" if redirects_left.negative?

    response = Net::HTTP.get_response(URI(url))
    case response
    when Net::HTTPRedirection then download(response.fetch('location'), redirects_left - 1)
    when Net::HTTPSuccess then response.body
    else raise "GET #{url} failed: #{response.code} #{response.message}"
    end
  end

  def fetch_tarball(version)
    url = ZSVUpstream.tarball_url(version)
    puts "Downloading #{url}"
    download(url)
  end

  def verify_checksum!(tarball, expected)
    actual = Digest::SHA256.hexdigest(tarball)
    return if actual == expected

    abort "SHA-256 mismatch for zsv tarball: expected #{expected}, got #{actual}. " \
          'Refusing to vendor it.'
  end

  # Extracts only ZSVUpstream::VENDORED_PATHS from the tarball into dest.
  def extract(tarball, version, dest)
    prefix = "zsv-#{version}/"
    Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(tarball))) do |tar|
      tar.each do |entry|
        relative = vendored_relative_path(entry.full_name, prefix) or next
        write_entry(entry, File.join(dest, relative))
      end
    end
    missing = ZSVUpstream::VENDORED_PATHS.reject { |path| File.exist?(File.join(dest, path)) }
    abort "zsv tarball is missing #{missing.join(', ')}" unless missing.empty?
  end

  def vendored_relative_path(name, prefix)
    return unless name.start_with?(prefix)

    relative = name.delete_prefix(prefix)
    return unless ZSVUpstream::VENDORED_PATHS.include?(relative.split('/').first)
    raise "Unsafe path in zsv tarball: #{name}" if relative.split('/').include?('..')

    relative
  end

  def write_entry(entry, path)
    if entry.directory?
      FileUtils.mkdir_p(path)
    elsif entry.file?
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, entry.read)
      File.chmod(entry.header.mode.anybits?(0o100) ? 0o755 : 0o644, path)
    else
      raise "Unexpected non-regular entry in zsv tarball: #{entry.full_name}"
    end
  end

  # Verifies the tarball against the pin and extracts it into a fresh directory.
  def build_tree(pin, dest, tarball = fetch_tarball(pin.fetch('version')))
    verify_checksum!(tarball, pin.fetch('sha256'))
    extract(tarball, pin.fetch('version'), dest)
    marker = File.join(dest, File.basename(ZSVUpstream::MARKER_FILE))
    File.write(marker, ZSVUpstream.marker_for(pin))
    File.chmod(0o644, marker)
  end

  # @return [Hash{String => Array}] relative path => [content digest, executable?]
  # (git keeps only the executable bit, so other mode bits depend on the umask)
  def tree_snapshot(root)
    Dir.glob('**/*', File::FNM_DOTMATCH, base: root).each_with_object({}) do |relative, snapshot|
      path = File.join(root, relative)
      next unless File.file?(path)

      snapshot[relative] = [Digest::SHA256.file(path).hexdigest, File.executable?(path)]
    end
  end

  def vendor!(pin, tarball = fetch_tarball(pin.fetch('version')))
    Dir.mktmpdir('zsv-vendor') do |tmp|
      tree = File.join(tmp, 'zsv')
      build_tree(pin, tree, tarball)
      FileUtils.rm_rf(ZSVUpstream::VENDOR_DIR)
      FileUtils.mkdir_p(File.dirname(ZSVUpstream::VENDOR_DIR))
      FileUtils.cp_r(tree, ZSVUpstream::VENDOR_DIR)
    end
    puts "Vendored zsv #{pin.fetch('version')} into #{ZSVUpstream::VENDOR_DIR}"
  end

  def verify!(pin)
    Dir.mktmpdir('zsv-verify') do |tmp|
      build_tree(pin, tmp)
      expected = tree_snapshot(tmp)
      actual = tree_snapshot(ZSVUpstream::VENDOR_DIR)
      differing = (expected.keys | actual.keys).reject { |path| expected[path] == actual[path] }
      abort "ext/zsv/vendor/zsv differs from zsv #{pin['version']} in: #{differing.sort.join(', ')}" \
        unless differing.empty?
    end
    puts "ext/zsv/vendor/zsv matches zsv #{pin['version']} (sha256 #{pin['sha256']})"
  end

  # Pins a new release by the SHA-256 of its tarball, then vendors that tarball.
  def bump!(version)
    tarball = fetch_tarball(version)
    sha256 = Digest::SHA256.hexdigest(tarball)
    ZSVUpstream.validate!({ 'version' => version, 'sha256' => sha256 }, 'zsv:bump')
    write_pin(version, sha256)
    puts "Pinned zsv #{version} (sha256 #{sha256})"
    vendor!(ZSVUpstream.pin, tarball)
  end

  def write_pin(version, sha256)
    lines = File.readlines(ZSVUpstream::PIN_FILE).map do |line|
      line.sub(/\Aversion=.*/, "version=#{version}").sub(/\Asha256=.*/, "sha256=#{sha256}")
    end
    File.write(ZSVUpstream::PIN_FILE, lines.join)
  end
end

namespace :zsv do
  desc 'Download the zsv release pinned in ext/zsv/ZSV_UPSTREAM, verify its SHA-256, vendor it'
  task :vendor do
    ZSVVendor.vendor!(ZSVUpstream.pin)
  end

  desc 'Fail unless ext/zsv/vendor/zsv was vendored from the current ext/zsv/ZSV_UPSTREAM (offline)'
  task :check do
    abort 'ext/zsv/vendor/zsv does not match ext/zsv/ZSV_UPSTREAM: run `bundle exec rake zsv:vendor`' \
      unless ZSVUpstream.vendored_current?
  end

  desc 'Fail unless ext/zsv/vendor/zsv is identical to the pinned, checksum-verified release'
  task :verify do
    ZSVVendor.verify!(ZSVUpstream.pin)
  end

  desc 'Pin a new zsv release (rewrites ext/zsv/ZSV_UPSTREAM with its SHA-256) and vendor it'
  task :bump, [:version] do |_task, args|
    ZSVVendor.bump!(args.fetch(:version) { abort 'usage: rake "zsv:bump[1.4.5]"' })
  end
end
