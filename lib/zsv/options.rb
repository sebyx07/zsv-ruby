# frozen_string_literal: true

module ZSV
  # Validates the keyword options of the public API and converts them into
  # the hash the C extension understands, so that an unsupported or misspelled
  # option raises instead of being silently ignored.
  module Options
    # Options interpreted (or validated) by the Ruby layer
    RUBY_KEYS = %i[headers col_sep quote_char row_sep skip_lines liberal_parsing encoding buffer_size].freeze
    # Options handed to the C extension untouched
    NATIVE_KEYS = %i[max_columns max_row_size].freeze
    KNOWN_KEYS = (RUBY_KEYS + NATIVE_KEYS).freeze

    ROW_SEPARATORS = [:auto, "\n", "\r\n", "\r"].freeze
    QUOTE_CHAR = '"'
    DEFAULT_COL_SEP = ','

    module_function

    # @param options [Hash] keyword options given by the caller
    # @return [Hash] options for the C extension
    # @raise [ArgumentError] for unknown keys and unsupported values
    def normalize(options)
      check(options)
      col_sep = col_sep(options)

      options.slice(*NATIVE_KEYS).merge(
        col_sep: col_sep,
        headers: headers(options[:headers], col_sep),
        skip_lines: skip_lines(options[:skip_lines]),
        encoding: encoding(options[:encoding]),
        buffer_size: buffer_size(options[:buffer_size])
      ).compact
    end

    # Rejects the options ZSV cannot honour.
    def check(options)
      reject_unknown_keys(options)
      check_quote_char(options[:quote_char]) if options.key?(:quote_char)
      check_row_sep(options[:row_sep]) if options.key?(:row_sep)
      check_liberal_parsing(options[:liberal_parsing])
    end

    # @return [Boolean] true when quoting errors must raise (liberal_parsing: false)
    def strict?(options)
      options[:liberal_parsing] == false
    end

    # @return [String] the validated single-byte column separator
    def col_sep(options)
      col_sep = options.fetch(:col_sep, nil) || DEFAULT_COL_SEP
      raise ArgumentError, "col_sep must be a String, got #{col_sep.inspect}" unless col_sep.is_a?(String)

      unless col_sep.bytesize == 1 && col_sep.ascii_only?
        raise ArgumentError, "col_sep must be a single ASCII character (zsv limitation), got #{col_sep.inspect}"
      end
      if [QUOTE_CHAR, "\n", "\r"].include?(col_sep)
        raise ArgumentError, "col_sep cannot be a quote or a line ending, got #{col_sep.inspect}"
      end

      col_sep
    end

    def reject_unknown_keys(options)
      unknown = options.keys - KNOWN_KEYS
      return if unknown.empty?

      raise ArgumentError, "unknown keyword#{'s' if unknown.size > 1}: #{unknown.map(&:inspect).join(', ')}"
    end

    def check_quote_char(quote_char)
      return if quote_char == QUOTE_CHAR

      raise ArgumentError, "quote_char must be '\"': zsv supports no other quote character, got #{quote_char.inspect}"
    end

    def check_row_sep(row_sep)
      return if ROW_SEPARATORS.include?(row_sep)

      raise ArgumentError,
            'row_sep must be :auto, "\n", "\r\n" or "\r": zsv always auto-detects these line endings, ' \
            "got #{row_sep.inspect}"
    end

    def check_liberal_parsing(liberal_parsing)
      return if [nil, true, false].include?(liberal_parsing)

      raise ArgumentError, "liberal_parsing must be true or false, got #{liberal_parsing.inspect}"
    end

    def headers(headers, col_sep)
      case headers
      when nil, false then nil
      when true, :first_row then true
      when Array then headers
      when String then header_line(headers, col_sep)
      else raise ArgumentError, "headers must be true, false, an Array or a String, got #{headers.inspect}"
      end
    end

    # CSV accepts the header names as one CSV line
    def header_line(line, col_sep)
      ZSV.parse_line(line, col_sep: col_sep) || []
    end

    def skip_lines(skip_lines)
      return skip_lines if skip_lines.nil? || (skip_lines.is_a?(Integer) && !skip_lines.negative?)

      raise ArgumentError,
            'skip_lines must be a non-negative Integer (the number of leading rows to drop); ' \
            "CSV-style matchers are not supported, got #{skip_lines.inspect}"
    end

    # Accepts an Encoding, a name, and the CSV forms "bom|utf-8" (zsv always
    # strips a UTF-8 BOM) and "ext:int" when no transcoding is asked for.
    def encoding(encoding)
      return encoding if encoding.nil? || encoding.is_a?(Encoding)

      external, internal = encoding.to_s.sub(/\Abom\|/i, '').split(':', 2)
      found = Encoding.find(external)
      return found if internal.nil? || internal == '-' || Encoding.find(internal) == found

      raise ArgumentError, "transcoding (#{encoding.inspect}) is not supported: fields keep the source bytes"
    end

    def buffer_size(buffer_size)
      return buffer_size if buffer_size.nil? || (buffer_size.is_a?(Integer) && buffer_size.positive?)

      raise ArgumentError, "buffer_size must be a positive Integer, got #{buffer_size.inspect}"
    end
  end
end
