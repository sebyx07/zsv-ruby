# frozen_string_literal: true

# The pinned upstream zsv release, shared by the Rakefile (which vendors it)
# and extconf.rb (which builds it). The pin itself lives in ZSV_UPSTREAM.
module ZSVUpstream
  PIN_FILE = File.expand_path('ZSV_UPSTREAM', __dir__)
  VENDOR_DIR = File.expand_path('vendor/zsv', __dir__)
  # Written into VENDOR_DIR by `rake zsv:vendor`; records which pin it came from.
  MARKER_FILE = File.join(VENDOR_DIR, 'VENDORED_FROM')
  # The only parts of the upstream tarball needed to build libzsv.
  VENDORED_PATHS = %w[LICENSE configure include src].freeze

  module_function

  # @return [Hash{String => String}] the pin, e.g. {'version' => '1.4.4', 'sha256' => '...'}
  def pin(path = PIN_FILE)
    entries = File.readlines(path, chomp: true).reject { |line| line.strip.empty? || line.start_with?('#') }
    pin = entries.to_h { |line| line.split('=', 2).map(&:strip) }
    validate!(pin, path)
  end

  def version
    pin.fetch('version')
  end

  def sha256
    pin.fetch('sha256')
  end

  def tarball_url(version = self.version)
    "https://github.com/liquidaty/zsv/archive/refs/tags/v#{version}.tar.gz"
  end

  # @return [String, nil] contents of the marker, nil when nothing is vendored
  def vendored_marker
    File.read(MARKER_FILE) if File.file?(MARKER_FILE)
  end

  def marker_for(pin)
    "version=#{pin.fetch('version')}\nsha256=#{pin.fetch('sha256')}\n"
  end

  def vendored_current?
    vendored_marker == marker_for(pin)
  end

  def validate!(pin, path)
    raise ArgumentError, "#{path}: version must look like 1.2.3, got #{pin['version'].inspect}" \
      unless pin['version'].to_s.match?(/\A\d+(\.\d+){2}\z/)
    raise ArgumentError, "#{path}: sha256 must be 64 hex characters, got #{pin['sha256'].inspect}" \
      unless pin['sha256'].to_s.match?(/\A\h{64}\z/)

    pin
  end
end
