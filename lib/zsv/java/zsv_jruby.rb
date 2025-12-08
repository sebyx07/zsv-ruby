# frozen_string_literal: true

# JRuby entry point for ZSV - uses Java/JNI native parser
require 'java'

module ZSV
  # Load native library via Java class
  def self.load_native
    return if defined?(@native_loaded)

    @native_loaded = false
    java_dir = File.dirname(__FILE__)
    classes_dir = File.join(java_dir, 'classes')

    $CLASSPATH << classes_dir if File.directory?(classes_dir)

    begin
      java_import 'zsv.ZsvParser'
      java_import 'zsv.ZsvNative'

      native_lib = File.join(java_dir, 'libzsv_jni.so')
      @native_loaded = Java::Zsv::ZsvNative.loadLibrary(native_lib) if File.exist?(native_lib)
    rescue NameError, Java::JavaLang::NoClassDefFoundError
      @native_loaded = false
    end
  end

  def self.native_available?
    load_native
    @native_loaded
  end

  # Parser class - thin wrapper around Java ZsvParser
  class Parser
    include Enumerable

    def initialize(source, **options)
      ZSV.load_native
      raise 'ZSV native library not available' unless ZSV.native_available?

      @options = options
      @closed = false

      java_options = java.util.HashMap.new
      java_options.put('col_sep', options[:col_sep] || ',')
      java_options.put('quote_char', options[:quote_char] || '"')
      java_options.put('skip_lines', options[:skip_lines] || 0)

      case options[:headers]
      when true
        java_options.put('headers', true)
        @use_headers = true
      when Array
        java_options.put('headers', options[:headers].to_java(:string))
        @use_headers = true
        @headers = options[:headers]
      end

      @java_parser = if source.is_a?(String) && (source.empty? || source.include?("\n") || source.include?(','))
                       Java::Zsv::ZsvParser.from_string(source, java_options)
                     elsif source.is_a?(String)
                       Java::Zsv::ZsvParser.new(source, java_options)
                     else
                       Java::Zsv::ZsvParser.from_string(source.read, java_options)
                     end
    end

    def shift
      return nil if @closed

      row = @java_parser.shift
      return nil if row.nil?

      ruby_row = row.to_a

      @headers ||= @java_parser.getHeaders&.to_a if @use_headers

      @headers ? build_hash(ruby_row) : ruby_row
    end

    def each
      return enum_for(:each) unless block_given?

      while (row = shift)
        yield row
      end
      nil
    end

    alias each_row each

    def rewind
      @java_parser.rewind
      nil
    end

    def close
      return if @closed

      @closed = true
      @java_parser.close
      nil
    end

    def closed?
      @closed
    end

    def headers
      @headers ||= @java_parser.getHeaders&.to_a if @use_headers
      @headers
    end

    def read
      to_a
    end

    private

    def build_hash(row)
      result = {}
      @headers.each_with_index { |h, i| result[h] = row[i] if i < row.length }
      ((@headers.length)...row.length).each { |i| result[i.to_s] = row[i] }
      result
    end
  end

  # Module methods
  class << self
    def new(io, **options)
      Parser.new(io, **options)
    end

    def parse(string, **options)
      parser = Parser.new(string, **options)
      parser.read
    ensure
      parser&.close
    end

    def foreach(path, **options, &block)
      return enum_for(:foreach, path, **options) unless block_given?

      parser = Parser.new(path, **options)
      parser.each(&block)
    ensure
      parser&.close
    end

    def read(path, **options)
      parser = Parser.new(path, **options)
      parser.read
    ensure
      parser&.close
    end

    def open(path, mode = 'r', **options)
      raise NotImplementedError, 'Only read mode supported' if mode != 'r'

      parser = Parser.new(path, **options)
      return parser unless block_given?

      begin
        yield parser
      ensure
        parser.close
      end
    end
  end

  # Error classes
  class Error < StandardError; end
  class MalformedCSVError < Error; end
  class InvalidEncodingError < Error; end
end
