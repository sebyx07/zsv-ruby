# frozen_string_literal: true

require_relative 'zsv/version'

# Load the appropriate extension based on Ruby platform
if RUBY_PLATFORM == 'java'
  require_relative 'zsv/java/zsv_jruby'
else
  require_relative 'zsv/zsv' # Load C extension
end

# ZSV - SIMD-accelerated CSV parser
#
# A drop-in replacement for Ruby's CSV stdlib that uses the zsv C library
# for 10-50x performance improvements on large CSV files.
#
# @example Basic usage
#   ZSV.foreach("data.csv") do |row|
#     puts row.inspect
#   end
#
# @example With headers
#   ZSV.foreach("data.csv", headers: true) do |row|
#     puts row["name"]
#   end
#
# @example Parse string
#   rows = ZSV.parse("a,b,c\n1,2,3\n")
#
module ZSV
  class << self
    # Create a new parser instance
    #
    # This is a convenience method that creates a Parser object.
    #
    # @param io [String, IO] File path or IO object to parse
    # @param options [Hash] Parser options
    # @return [Parser] New parser instance
    #
    # @example
    #   parser = ZSV.new("data.csv", headers: true)
    #   parser.each { |row| puts row }
    #   parser.close
    #
    def new(io, **options)
      Parser.new(io, **options)
    end

    # Parse CSV data and return an Enumerator
    #
    # This method provides lazy enumeration over CSV rows without loading
    # the entire file into memory.
    #
    # @param source [String, IO] CSV data or IO object
    # @param options [Hash] Parser options
    # @return [Enumerator] Lazy enumerator over rows
    #
    # @example
    #   enum = ZSV.parse_enum("a,b\n1,2\n3,4", headers: true)
    #   enum.first # => {"a" => "1", "b" => "2"}
    #
    def parse_enum(source, **options)
      parser = Parser.new(source, **options)

      Enumerator.new do |yielder|
        parser.each { |row| yielder << row }
      ensure
        parser.close
      end
    end
  end

  # Parser class methods for convenience
  class Parser
    # Read all rows and return as an array
    #
    # @return [Array<Array, Hash>] All rows
    def read
      rows = []
      each { |row| rows << row }
      rows
    end

    # Alias for compatibility
    alias to_a read
  end
end
