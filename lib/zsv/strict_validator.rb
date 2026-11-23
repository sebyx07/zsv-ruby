# frozen_string_literal: true

require 'strscan'

module ZSV
  # Checks that input is well-formed CSV the way Ruby's CSV does in its
  # default (non-liberal) mode. zsv itself never rejects input, so this pass
  # is what backs +liberal_parsing: false+.
  #
  # The input is read one physical line at a time. A line without a quote is
  # accepted as is, and a line that is one well-formed record is accepted by a
  # single regexp match; only the rest (fields spanning lines, errors) is
  # scanned field by field.
  #
  # Errors carry the number CSV reports: the 1-based record, where a quoted
  # field that spans several lines counts once. Records are told apart by
  # "\n" (so "\r\n" works too); input using a lone "\r" is one record here.
  class StrictValidator
    QUOTE = '"'
    BOM = "\xEF\xBB\xBF".b.freeze
    ROW_END = /\r\n|\n|\r/
    QUOTED_BODY = /(?:[^"]+|"")*/

    # @param string [String] CSV data
    # @param col_sep [String] single-character column separator
    # @raise [MalformedCSVError, InvalidEncodingError]
    def self.validate_string(string, col_sep:)
      unless string.valid_encoding?
        new(col_sep, string.encoding).validate(string.each_line("\n"))
        return
      end
      return unless string.include?(QUOTE)

      new(col_sep, nil).validate(string.each_line("\n"))
    end

    # @param path [String] file to check
    # @param col_sep [String] single-character column separator
    # @param encoding [Encoding] encoding the fields will be labelled with
    # @raise [MalformedCSVError, InvalidEncodingError]
    def self.validate_file(path, col_sep:, encoding:)
      File.open(path, 'rb') do |file|
        new(col_sep, encoding).validate(file.each_line("\n"))
      end
    end

    # @param col_sep [String] single-character column separator
    # @param encoding [Encoding, nil] encoding to verify each line against, nil to skip
    def initialize(col_sep, encoding)
      separator = Regexp.escape(col_sep)
      field = /(?>"(?>[^"]+|"")*"|[^"#{separator}\r\n]*)/
      @col_sep = col_sep
      @unquoted = /[^"#{separator}\r\n]*/
      @complete_record = /\A#{field}(?>#{separator}#{field})*\r?\n?\z/
      @encoding = encoding
    end

    # @param lines [Enumerable<String>] physical lines, including their "\n"
    # @raise [MalformedCSVError, InvalidEncodingError]
    # @return [void]
    def validate(lines)
      record = 0
      in_quotes = false

      lines.each_with_index do |line, index|
        record += 1 unless in_quotes
        check_encoding(line, record, first_line: index.zero?)
        next if !in_quotes && (!line.include?(QUOTE) || line.match?(@complete_record))

        in_quotes = scan(line, in_quotes, record, first_line: index.zero?)
      end

      raise MalformedCSVError.new('Unclosed quoted field', record) if in_quotes
    end

    private

    def check_encoding(line, record, first_line:)
      return unless @encoding

      line = line.byteslice(BOM.bytesize..) if first_line && line.b.start_with?(BOM)
      return if line.force_encoding(@encoding).valid_encoding?

      raise InvalidEncodingError.new("Invalid byte sequence in #{@encoding}", record)
    end

    # Scans one physical line. Returns true when it ends inside a quoted field.
    def scan(line, in_quotes, record, first_line:)
      scanner = StringScanner.new(line.b)
      scanner.skip(BOM) if first_line

      until scanner.eos?
        if in_quotes
          return true unless close_quoted_field(scanner, record)

          in_quotes = false
        elsif scanner.skip(QUOTE)
          in_quotes = true
        else
          skip_unquoted_field(scanner, record)
        end
      end
      in_quotes
    end

    # Returns false when the line ends before the closing quote.
    def close_quoted_field(scanner, record)
      scanner.skip(QUOTED_BODY)
      return false if scanner.eos?

      scanner.skip(QUOTE)
      return true if scanner.eos? || scanner.skip(@col_sep) || scanner.skip(ROW_END)

      raise MalformedCSVError.new("Any value after quoted field isn't allowed", record)
    end

    def skip_unquoted_field(scanner, record)
      scanner.skip(@unquoted)
      return if scanner.eos? || scanner.skip(@col_sep) || scanner.skip(ROW_END)

      raise MalformedCSVError.new('Illegal quoting', record)
    end
  end
end
