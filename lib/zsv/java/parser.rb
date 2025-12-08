# frozen_string_literal: true

# JRuby implementation of ZSV::Parser using Java classes

require 'java'
require 'stringio'

module ZSV
  # Parser class for JRuby - wraps the Java ZsvParser
  class Parser
    include Enumerable

    # Load Java classes
    def self.load_java_classes
      return if @java_loaded

      # Try to load the compiled Java classes
      begin
        java_import 'zsv.ZsvParser'
        java_import 'zsv.ZsvNative'
        @java_loaded = true
        @native_available = Java::Zsv::ZsvNative.available?
      rescue NameError, Java::JavaLang::NoClassDefFoundError
        # Java classes not found, use pure Ruby fallback
        @java_loaded = false
        @native_available = false
      end
    end

    def self.java_loaded?
      @java_loaded || false
    end

    def self.native_available?
      @native_available || false
    end

    def initialize(source, **options)
      self.class.load_java_classes

      @options = options
      @headers = nil
      @use_headers = false
      @custom_headers = nil
      @closed = false

      parse_options(options)

      if self.class.java_loaded?
        init_java_parser(source, options)
      else
        init_ruby_parser(source, options)
      end
    end

    # Read and return next row
    def shift
      return nil if @closed

      if @java_parser
        shift_java
      else
        shift_ruby
      end
    end

    # Iterate over all rows
    def each
      return enum_for(:each) unless block_given?

      while (row = shift)
        yield row
      end

      nil
    end

    alias each_row each

    # Rewind to beginning
    def rewind
      if @java_parser
        @java_parser.rewind
        @header_row_processed = false unless @custom_headers
        @headers = @custom_headers
      elsif @file_path
        @file&.close
        @file = File.open(@file_path, 'rb')
        @header_row_processed = false unless @custom_headers
        @headers = @custom_headers
      elsif @string_data
        @string_io = StringIO.new(@string_data)
        @header_row_processed = false unless @custom_headers
        @headers = @custom_headers
      end

      nil
    end

    # Close the parser
    def close
      return if @closed

      @closed = true

      if @java_parser
        @java_parser.close
      else
        @file&.close
      end

      nil
    end

    # Get headers
    attr_reader :headers

    # Check if closed
    def closed?
      @closed
    end

    # Read all rows
    def read
      rows = []
      each { |row| rows << row }
      rows
    end

    alias to_a read

    private

    def parse_options(options)
      @delimiter = options[:col_sep] || ','
      @quote_char = options[:quote_char] || '"'
      @skip_lines = options[:skip_lines] || 0
      @lines_skipped = 0
      @header_row_processed = false

      case options[:headers]
      when true
        @use_headers = true
      when Array
        @use_headers = true
        @custom_headers = options[:headers]
        @headers = @custom_headers
        @header_row_processed = true
      when false, nil
        @use_headers = false
      end
    end

    def init_java_parser(source, _options)
      java_options = java.util.HashMap.new
      java_options.put('col_sep', @delimiter)
      java_options.put('quote_char', @quote_char)
      java_options.put('skip_lines', @skip_lines)

      if @custom_headers
        java_options.put('headers', @custom_headers.to_java(:string))
      elsif @use_headers
        java_options.put('headers', true)
      end

      if source.is_a?(String)
        if looks_like_csv_data?(source)
          @java_parser = Java::Zsv::ZsvParser.from_string(source, java_options)
        else
          @java_parser = Java::Zsv::ZsvParser.new(source, java_options)
          @file_path = source
        end
      else
        # IO object - read all content
        content = source.read
        @java_parser = Java::Zsv::ZsvParser.from_string(content, java_options)
      end
    end

    def init_ruby_parser(source, _options)
      @java_parser = nil

      if source.is_a?(String)
        if looks_like_csv_data?(source)
          @string_data = source
          @string_io = StringIO.new(source)
        else
          @file_path = source
          @file = File.open(source, 'rb')
        end
      else
        # IO object
        @file = source
      end
    end

    def looks_like_csv_data?(str)
      str.empty? || str.include?("\n") || str.include?(',')
    end

    def shift_java
      row = @java_parser.shift

      return nil if row.nil?

      # Convert Java String array to Ruby array
      ruby_row = row.to_a

      # Handle headers
      if @use_headers && !@header_row_processed
        @headers = ruby_row
        @header_row_processed = true
        return shift_java
      end

      if @headers
        build_hash(ruby_row)
      else
        ruby_row
      end
    end

    def shift_ruby
      io = @file || @string_io
      return nil if io.nil?

      line = io.gets
      return nil if line.nil?

      row = parse_line(line, io)

      # Skip lines
      if @lines_skipped < @skip_lines
        @lines_skipped += 1
        return shift_ruby
      end

      # Handle headers
      if @use_headers && !@header_row_processed
        @headers = row
        @header_row_processed = true
        return shift_ruby
      end

      if @headers
        build_hash(row)
      else
        row
      end
    end

    def parse_line(line, io)
      fields = []
      field = +''
      in_quotes = false

      line = line.chomp

      # Handle multiline fields - keep reading until quotes are closed
      loop do
        i = 0
        while i < line.length
          c = line[i]

          if in_quotes
            if c == @quote_char
              if i + 1 < line.length && line[i + 1] == @quote_char
                field << @quote_char
                i += 2
              else
                in_quotes = false
                i += 1
              end
            else
              field << c
              i += 1
            end
          elsif c == @quote_char
            in_quotes = true
            i += 1
          elsif c == @delimiter
            fields << field
            field = +''
            i += 1
          else
            field << c
            i += 1
          end
        end

        # If still in quotes, read more lines
        break unless in_quotes

        next_line = io.gets
        break unless next_line

        field << "\n"
        line = next_line.chomp
      end

      fields << field
      fields
    end

    def build_hash(row)
      result = {}
      @headers.each_with_index do |header, i|
        result[header] = row[i] if i < row.length
      end
      # Handle extra columns
      ((@headers.length)...row.length).each do |i|
        result[i.to_s] = row[i]
      end
      result
    end
  end

  # Exception classes
  class Error < StandardError; end
  class MalformedCSVError < Error; end
  class InvalidEncodingError < Error; end
end
