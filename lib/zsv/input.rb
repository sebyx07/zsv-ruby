# frozen_string_literal: true

module ZSV
  # Turns what the caller passed (CSV text, a path, an IO) plus its options
  # into the arguments of the C extension, running the strict check when
  # +liberal_parsing: false+ asks for it.
  module Input
    READ_MODE = /\Ar[bt]?(?::(?<encoding>.+))?\z/

    module_function

    # @param string [String] CSV data
    # @param options [Hash] keyword options given by the caller
    # @return [Array(String, Hash)] data and options for the C extension
    def data(string, options)
      raise TypeError, "no implicit conversion of #{string.class} into String" unless string.is_a?(String)

      native = Options.normalize(options)
      string = string.encode(Encoding::UTF_8) unless string.encoding.ascii_compatible?
      native[:encoding] ||= string.encoding
      StrictValidator.validate_string(string, col_sep: Options.col_sep(options)) if Options.strict?(options)
      [string, native]
    end

    # @param path [String, #to_path] file to parse
    # @param mode [String] read mode, as given to CSV.open ("r", "rb", "r:bom|utf-8")
    # @param options [Hash] keyword options given by the caller
    # @return [Array(String, Hash)] path and options for the C extension
    def path(path, mode, options)
      path = File.path(path)
      native = Options.normalize(mode_options(mode).merge(options))
      encoding = native[:encoding] || Encoding::UTF_8
      check_ascii_compatible(encoding)

      if Options.strict?(options)
        StrictValidator.validate_file(path, col_sep: Options.col_sep(options), encoding: encoding)
      end
      [path, native]
    end

    # @param io [#read] source to parse as it is read
    # @param options [Hash] keyword options given by the caller
    # @return [Array(Object, Hash)] the IO and options for the C extension;
    #   fields are labelled with the IO's external encoding, as CSV does
    def io(io, options)
      native = Options.normalize(options)
      check_ascii_compatible(native[:encoding]) if native[:encoding]
      encoding = io.external_encoding if io.respond_to?(:external_encoding)
      native[:encoding] ||= encoding if encoding&.ascii_compatible?
      [io, native]
    end

    # The parser works on bytes: it cannot find separators in UTF-16 or UTF-32.
    def check_ascii_compatible(encoding)
      return if encoding.ascii_compatible?

      raise ArgumentError, "encoding must be ASCII-compatible for files and IOs, got #{encoding}"
    end

    # Decides what a String given to ZSV.new is: data when it is empty or
    # holds a line ending or a NUL byte, else the path of an existing file,
    # else data when it holds the column separator, else a path (which will
    # not be found).
    #
    # @return [Boolean] true for CSV data, false for a path
    def data?(string, col_sep)
      return true if string.empty? || string.match?(/[\r\n\0]/)
      return false if File.file?(string)

      string.include?(col_sep)
    end

    # A Pathname answers #read too, with the whole file each time: it is a
    # path, while a File (which has both) is a stream.
    #
    # @return [Boolean] true for a path-like object that is not a stream
    def path?(source)
      source.respond_to?(:to_path) && !source.respond_to?(:eof?)
    end

    def mode_options(mode)
      match = READ_MODE.match((mode || 'r').to_s)
      raise ArgumentError, "ZSV only reads CSV: unsupported mode #{mode.inspect}" unless match

      match[:encoding] ? { encoding: match[:encoding] } : {}
    end
  end
end
