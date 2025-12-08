# frozen_string_literal: true

# JRuby entry point for ZSV
# This file is loaded instead of the C extension when running on JRuby

require_relative 'parser'

module ZSV
  class << self
    # Create a new parser instance
    def new(io, **options)
      Parser.new(io, **options)
    end

    # Parse CSV string and return all rows
    def parse(string, **options)
      parser = Parser.new(string, **options)
      result = []
      parser.each { |row| result << row }
      result
    ensure
      parser&.close
    end

    # Iterate over CSV file rows
    def foreach(path, **options, &block)
      return enum_for(:foreach, path, **options) unless block_given?

      parser = Parser.new(path, **options)
      begin
        parser.each(&block)
      ensure
        parser.close
      end

      nil
    end

    # Read entire CSV file into array
    def read(path, **options)
      parser = Parser.new(path, **options)
      result = []
      parser.each { |row| result << row }
      result
    ensure
      parser&.close
    end

    # Open CSV file with optional block
    def open(path, mode = 'r', **options)
      raise NotImplementedError, 'Only read mode is currently supported' if mode != 'r'

      parser = Parser.new(path, **options)

      if block_given?
        begin
          yield parser
        ensure
          parser.close
        end
      else
        parser
      end
    end

    # Parse CSV data and return an Enumerator
    def parse_enum(source, **options)
      parser = Parser.new(source, **options)

      Enumerator.new do |yielder|
        parser.each { |row| yielder << row }
      ensure
        parser.close
      end
    end
  end
end
