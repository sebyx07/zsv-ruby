# frozen_string_literal: true

require_relative 'csv_compat_helper'
require 'stringio'

RSpec.describe 'ZSV options' do
  let(:data) { "a,b\n1,2\n" }

  def entry_points(path, **options)
    {
      parse: -> { ZSV.parse(File.read(path), **options) },
      read: -> { ZSV.read(path, **options) },
      foreach: -> { ZSV.foreach(path, **options) { |row| row } },
      'foreach without a block': -> { ZSV.foreach(path, **options) },
      open: -> { ZSV.open(path, **options, &:read) },
      new: -> { ZSV.new(path, **options).read },
      'Parser.new': -> { ZSV::Parser.new(File.read(path), **options).read }
    }
  end

  def expect_rejected(message, **options)
    with_csv_file(data) do |path|
      entry_points(path, **options).each do |name, call|
        expect(&call).to raise_error(ArgumentError, message), "#{name} accepted #{options}"
      end
    end
  end

  describe 'unknown options' do
    it 'raises like CSV instead of ignoring them' do
      expect { CSV.parse(data, bogus: 1) }.to raise_error(ArgumentError, /unknown keyword: :bogus/)
      expect_rejected(/unknown keyword: :bogus/, bogus: 1)
    end

    it 'rejects CSV options ZSV does not implement' do
      %i[converters header_converters skip_blanks strip nil_value return_headers].each do |option|
        expect { ZSV.parse(data, option => true) }.to raise_error(ArgumentError, /unknown keyword: :#{option}/)
      end
    end

    it 'names every unknown option' do
      expect { ZSV.parse(data, foo: 1, bar: 2) }.to raise_error(ArgumentError, 'unknown keywords: :foo, :bar')
    end
  end

  describe 'col_sep' do
    it 'rejects a multi-character separator, which CSV accepts' do
      expect(CSV.parse("a::b\n", col_sep: '::')).to eq([%w[a b]])
      expect_rejected(/col_sep must be a single ASCII character/, col_sep: '::')
    end

    it 'rejects an empty, multi-byte or non-String separator' do
      ['', 'é', :tab, 9].each do |col_sep|
        expect { ZSV.parse(data, col_sep: col_sep) }.to raise_error(ArgumentError, /col_sep must be/)
      end
    end

    it 'rejects a quote or a line ending' do
      ['"', "\n", "\r"].each do |col_sep|
        expect { ZSV.parse(data, col_sep: col_sep) }.to raise_error(ArgumentError, /col_sep cannot be/)
      end
    end

    it 'treats nil as the default' do
      expect(ZSV.parse(data, col_sep: nil)).to eq([%w[a b], %w[1 2]])
    end
  end

  describe 'quote_char' do
    it 'accepts the double quote' do
      expect(ZSV.parse(%(a,"b,c"\n), quote_char: '"')).to eq([['a', 'b,c']])
    end

    it 'rejects any other quote character, which CSV accepts' do
      expect(CSV.parse("a,'b,c'\n", quote_char: "'")).to eq([['a', 'b,c']])
      expect_rejected(/quote_char must be '"'/, quote_char: "'")
    end

    it 'rejects nil, which disables quoting in CSV' do
      expect { ZSV.parse(data, quote_char: nil) }.to raise_error(ArgumentError, /quote_char must be/)
    end
  end

  describe 'row_sep' do
    it 'rejects a custom separator, which CSV accepts' do
      expect(CSV.parse('a,b|1,2|', row_sep: '|')).to eq([%w[a b], %w[1 2]])
      expect_rejected(/row_sep must be :auto/, row_sep: '|')
    end
  end

  describe 'skip_lines' do
    it 'drops that many leading rows' do
      expect(ZSV.parse("x\ny\na,b\n1,2\n", skip_lines: 2)).to eq([%w[a b], %w[1 2]])
    end

    it 'drops rows before the header row' do
      expect(ZSV.parse("generated 2024\na,b\n1,2\n", skip_lines: 1, headers: true))
        .to eq([{ 'a' => '1', 'b' => '2' }])
    end

    it 'counts a quoted field with a line break as one row' do
      expect(ZSV.parse(%("x\ny",z\na,b\n), skip_lines: 1)).to eq([%w[a b]])
    end

    it 'returns no rows when it exceeds the row count' do
      expect(ZSV.parse(data, skip_lines: 5)).to eq([])
    end

    it 'applies to files' do
      with_csv_file("x\na,b\n") do |path|
        expect(ZSV.read(path, skip_lines: 1)).to eq([%w[a b]])
        expect(ZSV.foreach(path, skip_lines: 1).to_a).to eq([%w[a b]])
      end
    end

    it 'rejects the matchers CSV takes, and negative counts' do
      expect(CSV.parse("#c\na,b\n", skip_lines: /\A#/)).to eq([%w[a b]])
      expect_rejected(/skip_lines must be a non-negative Integer/, skip_lines: /\A#/)
      expect { ZSV.parse(data, skip_lines: '#') }.to raise_error(ArgumentError, /skip_lines must be/)
      expect { ZSV.parse(data, skip_lines: -1) }.to raise_error(ArgumentError, /skip_lines must be/)
    end
  end

  describe 'headers' do
    it 'rejects values that are not true, false, an Array or a String' do
      expect { ZSV.parse(data, headers: 1) }.to raise_error(ArgumentError, /headers must be/)
      expect { ZSV.parse(data, headers: :symbol) }.to raise_error(ArgumentError, /headers must be/)
    end

    it 'treats false and nil as no headers' do
      expect(ZSV.parse(data, headers: false)).to eq([%w[a b], %w[1 2]])
      expect(ZSV.parse(data, headers: nil)).to eq([%w[a b], %w[1 2]])
    end
  end

  describe 'encoding' do
    it 'labels fields with the encoding of the parsed String, like CSV' do
      sources = ["café,b\n", "caf\xE9,b\n".b.force_encoding(Encoding::ISO_8859_1), "caf\xE9,b\n".b]

      sources.each do |source|
        expect(ZSV.parse(source).flatten.map(&:encoding)).to eq(CSV.parse(source).flatten.map(&:encoding))
      end
    end

    it 'transcodes a String that is not ASCII-compatible to UTF-8' do
      rows = ZSV.parse("a,é\n1,2\n".encode(Encoding::UTF_16LE))

      expect(rows).to eq([%w[a é], %w[1 2]])
      expect(rows.flatten.map(&:encoding)).to all(eq(Encoding::UTF_8))
    end

    it 'labels the fields of a file as UTF-8 by default' do
      with_csv_file("é,b\n") do |path|
        expect(ZSV.read(path).flatten.map(&:encoding)).to all(eq(Encoding::UTF_8))
      end
    end

    it 'labels fields with the given encoding without transcoding' do
      with_csv_file("caf\xE9,b\n".b) do |path|
        field = ZSV.read(path, encoding: 'ISO-8859-1').first.first

        expect(field.encoding).to eq(Encoding::ISO_8859_1)
        expect(field.bytes).to eq("caf\xE9".bytes)
        expect(ZSV.read(path, encoding: Encoding::ISO_8859_1).first.first).to eq(field)
      end
    end

    it 'accepts the CSV "bom|utf-8" form' do
      with_csv_file("\xEF\xBB\xBFa,b\n") do |path|
        expect(ZSV.read(path, encoding: 'bom|utf-8')).to eq(CSV.read(path, encoding: 'bom|utf-8'))
        expect(ZSV.open(path, 'r:bom|utf-8', &:read)).to eq([%w[a b]])
      end
    end

    it 'accepts "ext:int" only when nothing has to be transcoded' do
      expect(ZSV.parse(data, encoding: 'UTF-8:UTF-8')).to eq([%w[a b], %w[1 2]])
      expect { ZSV.parse(data, encoding: 'ISO-8859-1:UTF-8') }
        .to raise_error(ArgumentError, /transcoding .* is not supported/)
    end

    it 'rejects an unknown encoding' do
      expect { ZSV.parse(data, encoding: 'nope') }.to raise_error(ArgumentError, /unknown encoding name/)
    end

    it 'rejects an encoding that is not ASCII-compatible for files and IOs' do
      with_csv_file(data) do |path|
        expect { ZSV.read(path, encoding: 'UTF-16LE') }.to raise_error(ArgumentError, /ASCII-compatible/)
      end
      expect { ZSV.new(StringIO.new(data), encoding: 'UTF-16LE') }.to raise_error(ArgumentError, /ASCII-compatible/)
    end

    it 'does not validate bytes in the default lenient mode' do
      field = ZSV.parse("a\xFFb,c\n").first.first

      expect(field.valid_encoding?).to be(false)
    end
  end

  describe 'buffer_size' do
    it 'does not change the result' do
      rows = Array.new(2_000) { |i| "#{i},value #{i}" }.join("\n")

      expect(ZSV.parse(rows, buffer_size: 4096)).to eq(ZSV.parse(rows))
    end

    it 'rejects values that are not a positive Integer' do
      [0, -1, '1024', 1.5].each do |buffer_size|
        expect { ZSV.parse(data, buffer_size: buffer_size) }.to raise_error(ArgumentError, /buffer_size must be/)
      end
    end
  end

  describe 'max_row_size' do
    # Every entry point over the same CSV text: they read through different C sources.
    def each_source(data, **options)
      with_csv_file(data) do |path|
        yield :path, -> { ZSV.read(path, **options) }
        yield :string, -> { ZSV.parse(data, **options) }
        yield :io, -> { ZSV.new(StringIO.new(data), **options).read }
        yield :foreach, -> { ZSV.foreach(path, **options).to_a }
      end
    end

    def expect_too_long(data, line, **options)
      each_source(data, **options) do |source, parse|
        expect(&parse).to raise_error(ZSV::MalformedCSVError, /longer than max_row_size/) { |error|
          expect([source, error.line_number]).to eq([source, line])
        }
      end
    end

    it 'parses a row longer than the read buffer completely when it is within the limit' do
      data = "a,b\n1,#{'x' * 300_000}\n2,y\n"

      each_source(data, max_row_size: 300_002) do |source, parse|
        expect([source, parse.call]).to eq([source, CSV.parse(data)])
      end
    end

    it 'raises instead of truncating a row longer than the default limit of 256 KiB' do
      expect(ZSV.parse("a,b\n1,#{'x' * 262_142}\n").last.last.size).to eq(262_142)
      expect_too_long("a,b\n1,#{'x' * 300_000}\n2,y\n", 2)
    end

    it 'raises for a row longer than a small limit, even one that fits in the read buffer' do
      expect_too_long("a,b\n#{'x' * 100}\n", 2, max_row_size: 10)
    end

    it 'counts the bytes of a row without its line ending, quotes included' do
      ["\n", "\r\n", "\r"].product(['', :terminated]).each do |row_sep, ending|
        last_sep = ending == :terminated ? row_sep : ''
        fits = "#{'x' * 4096}#{row_sep}\"#{'y' * 4094}\"#{last_sep}"
        each_source(fits, max_row_size: 4096, buffer_size: 4096) do |source, parse|
          expect([source, parse.call]).to eq([source, CSV.parse(fits, row_sep: row_sep)])
        end

        expect_too_long("a#{row_sep}#{'x' * 4097}#{row_sep}b#{last_sep}", 2, max_row_size: 4096, buffer_size: 4096)
        expect_too_long("a#{row_sep}\"#{'y' * 4095}\"#{last_sep}", 2, max_row_size: 4096, buffer_size: 4096)
      end
    end

    it 'parses a single field far larger than the read buffer from a stream' do
      field = 'z' * 3_000_000
      data = "h\n\"#{field}\"\nend\n"

      each_source(data, max_row_size: 3_000_002, buffer_size: 4096) do |source, parse|
        expect([source, parse.call]).to eq([source, [['h'], [field], ['end']]])
      end
    end

    it 'counts a quoted field spanning lines as one record in the line number' do
      expect_too_long("a\n\"1\n2\"\n#{'x' * 20}\n", 3, max_row_size: 10)
    end

    it 'streams many rows from an IO in small chunks' do
      data = Array.new(300_000) { |i| "#{i},v#{i}\n" }.join
      rows = ZSV.new(StringIO.new(data), buffer_size: 4096).read

      expect(rows.size).to eq(300_000)
      expect(rows.last).to eq(%w[299999 v299999])
    end

    it 'leaves no parser state behind when the error is raised under GC pressure', :slow do
      data = "a,b\n#{'x' * 64}\n"
      GC.stress = true
      3.times { expect_too_long(data, 2, max_row_size: 16) }
    ensure
      GC.stress = false
    end
  end

  describe 'liberal_parsing' do
    it 'rejects values that are not true or false' do
      expect { ZSV.parse(data, liberal_parsing: :yes) }.to raise_error(ArgumentError, /liberal_parsing must be/)
    end
  end
end
