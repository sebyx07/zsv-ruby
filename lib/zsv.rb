# frozen_string_literal: true

require_relative 'zsv/version'
# Load the C extension: precompiled gems ship one per Ruby minor
# (lib/zsv/3.4/zsv.so); source installs build lib/zsv/zsv.so.
begin
  require_relative "zsv/#{RUBY_VERSION[/\A\d+\.\d+/]}/zsv"
rescue LoadError
  require_relative 'zsv/zsv'
end
require_relative 'zsv/errors'
require_relative 'zsv/options'
require_relative 'zsv/strict_validator'
require_relative 'zsv/input'

# ZSV - SIMD-accelerated CSV parser
#
# A fast CSV reader built on the zsv C library, with an API modelled on the
# reading half of Ruby's CSV stdlib. Rows are plain Arrays (or Hashes with
# +headers:+) of frozen Strings. See docs/API_REFERENCE.md for the exact
# differences from CSV.
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
  # Ruby front of the module functions defined by the C extension: validates
  # options and input before handing over to C.
  module ModuleMethods
    # Parse a CSV String and return all rows.
    #
    # @param string [String] CSV data
    # @param options [Hash] parser options, see docs/API_REFERENCE.md
    # @return [Array<Array<String>>, Array<Hash>] all rows
    # @raise [ArgumentError] for unknown or unsupported options
    # @raise [MalformedCSVError] for malformed input with +liberal_parsing: false+
    def parse(string, **options)
      super(*Input.data(string, options))
    end

    # Parse a single CSV line.
    #
    # @param line [String] one CSV record
    # @param options [Hash] parser options
    # @return [Array<String>, Hash, nil] the first row, nil for an empty line
    def parse_line(line, **)
      parse(line, **).first
    end

    # Lazily enumerate the rows of a CSV String, a path or an IO.
    #
    # @param source [String, #to_path, #read] CSV data, a path or an IO
    # @param options [Hash] parser options
    # @return [Enumerator] rows, parsed as they are consumed
    def parse_enum(source, **)
      parser = Parser.new(source, **)

      Enumerator.new do |yielder|
        parser.each { |row| yielder << row }
      ensure
        parser.close
      end
    end

    # Stream the rows of a CSV file.
    #
    # @param path [String, #to_path] file to read
    # @param mode [String] read mode ("r", "rb", "r:bom|utf-8")
    # @param options [Hash] parser options
    # @yieldparam row [Array<String>, Hash]
    # @return [nil, Enumerator] an Enumerator when no block is given
    def foreach(path, mode = 'r', **options, &block)
      unless block
        Options.normalize(options) # report bad options now, not at the first row
        return to_enum(__method__, path, mode, **options)
      end

      super(*Input.path(path, mode, options), &block)
    end

    # Read a whole CSV file.
    #
    # @param path [String, #to_path] file to read
    # @param options [Hash] parser options
    # @return [Array<Array<String>>, Array<Hash>] all rows
    def read(path, **options)
      super(*Input.path(path, 'r', options))
    end

    # Open a CSV file for reading.
    #
    # @param path [String, #to_path] file to read
    # @param mode [String] read mode ("r", "rb", "r:bom|utf-8")
    # @param options [Hash] parser options
    # @yieldparam parser [Parser] closed when the block returns
    # @return [Parser, Object] the parser, or the block's value
    def open(path, mode = 'r', **options, &)
      path, native = Input.path(path, mode, options)
      super(path, native, &)
    end

    # Create a parser for CSV data, a path or an IO. See Parser.new.
    #
    # @return [Parser]
    def new(source, **)
      Parser.new(source, **)
    end
  end
  singleton_class.prepend(ModuleMethods)

  # Ruby front of Parser.new.
  module ParserConstruction
    # @param source [String, #read, #to_path] CSV data, a path or an IO.
    #   A String holding a line ending is data; otherwise it is a path when
    #   such a file exists, data when it contains the column separator, and
    #   a (missing) path in any other case. Use ZSV.parse or ZSV.open to
    #   avoid the guess. An IO is read as the rows are consumed.
    # @param options [Hash] parser options, see docs/API_REFERENCE.md
    # @return [Parser]
    def new(source, **options)
      if source.is_a?(String)
        return from_path(source, **options) unless Input.data?(source, Options.col_sep(options))

        from_string(source, **options)
      elsif Input.path?(source)
        from_path(source, **options)
      elsif source.respond_to?(:read)
        # Strict parsing has to see the whole input before the first row
        return from_string(source.read.to_s, **options) if Options.strict?(options)

        super(*Input.io(source, options))
      else
        raise TypeError, "expected CSV data, a path or an IO, got #{source.class}"
      end
    end

    # Create a parser over CSV data held in a String, never a path.
    #
    # @param string [String] CSV data
    # @param options [Hash] parser options
    # @return [Parser]
    def from_string(string, **options)
      super(*Input.data(string, options))
    end

    # Create a parser over a file.
    #
    # @param path [String, #to_path] file to read
    # @param options [Hash] parser options
    # @return [Parser]
    def from_path(path, **options)
      super(*Input.path(path, 'r', options))
    end
  end

  # Ruby front of the Parser instance methods defined by the C extension.
  module ParserMethods
    # Read all remaining rows.
    #
    # @return [Array<Array<String>>, Array<Hash>] remaining rows
    def read
      rows = []
      each { |row| rows << row }
      rows
    end
    alias to_a read
  end

  class Parser
    singleton_class.prepend(ParserConstruction)
    prepend ParserMethods
  end
end
