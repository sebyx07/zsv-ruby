# frozen_string_literal: true

require_relative 'csv_compat_helper'
require 'pathname'
require 'stringio'

RSpec.describe 'ZSV input and enumeration' do
  let(:data) { "a,b\n1,2\n3,4\n" }
  let(:rows) { [%w[a b], %w[1 2], %w[3 4]] }

  describe '.new' do
    it 'parses a String holding a line ending as CSV data' do
      expect(ZSV.new(data).read).to eq(rows)
      expect(ZSV.new("a;b\n", col_sep: ';').read).to eq([%w[a b]])
    end

    it 'reads an existing file given by path, even one with a comma in its name' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'a,b.csv')
        File.write(path, data)

        expect(ZSV.new(path).read).to eq(rows)
      end
    end

    it 'parses a one-line String holding the column separator as CSV data' do
      expect(ZSV.new('a,b').read).to eq([%w[a b]])
      expect(ZSV.new('a;b', col_sep: ';').read).to eq([%w[a b]])
    end

    it 'treats any other one-line String as a path' do
      expect { ZSV.new('missing.csv') }.to raise_error(Errno::ENOENT)
      expect { ZSV.new('a;b') }.to raise_error(Errno::ENOENT)
    end

    it 'parses an empty String and a String with a NUL byte as CSV data' do
      expect(ZSV.new('').read).to eq(CSV.new('').read)
      expect(ZSV.new("a\0b").read).to eq([["a\0b"]])
    end

    it 'reads a Pathname' do
      with_csv_file(data) do |path|
        expect(ZSV.new(Pathname(path)).read).to eq(rows)
      end
    end

    it 'reads an IO, like CSV.new' do
      expect(ZSV.new(StringIO.new(data)).read).to eq(CSV.new(StringIO.new(data)).read)
      with_csv_file(data) do |path|
        File.open(path) { |file| expect(ZSV.new(file, headers: true).read).to eq(csv_rows(data, headers: true)) }
      end
    end

    it 'labels the fields with the external encoding of the IO, like CSV' do
      [StringIO.new("a,b\n"), StringIO.new("a,b\n".b), StringIO.new("a,b\n".encode('ISO-8859-1'))].each do |io|
        expected = CSV.new(io).read.flatten.map(&:encoding)
        io.rewind

        expect(ZSV.new(io).read.flatten.map(&:encoding)).to eq(expected)
      end
    end

    it 'reads an IO in pieces, not all at once' do
      io = StringIO.new("a,b\n" * 200_000)
      parser = ZSV.new(io)
      parser.shift

      expect(io.pos).to be < io.size
    end

    it 'reads an empty IO as no rows' do
      parser = ZSV.new(StringIO.new(''))

      expect(parser.shift).to be_nil
      expect(parser.read).to eq([])
    end

    it 'rejects other sources' do
      expect { ZSV.new(42) }.to raise_error(TypeError, /expected CSV data, a path or an IO/)
    end

    it 'is not affected by later changes to the String' do
      source = +"a,b\n1,2\n"
      parser = ZSV.new(source)
      source.replace("x,y,z\n" * 20)
      GC.start

      expect(parser.read).to eq([%w[a b], %w[1 2]])
    end

    it 'offers from_string and from_path to avoid the guess' do
      expect(ZSV::Parser.from_string('missing.csv').read).to eq([['missing.csv']])
      expect { ZSV::Parser.from_path("a,b\n") }.to raise_error(Errno::ENOENT)
      expect { ZSV::Parser.from_string('a', bogus: 1) }.to raise_error(ArgumentError, /unknown keyword/)
      expect { ZSV::Parser.from_path('a', bogus: 1) }.to raise_error(ArgumentError, /unknown keyword/)
    end
  end

  describe '.parse' do
    it 'requires a String' do
      expect { ZSV.parse(nil) }.to raise_error(TypeError)
      expect { ZSV.parse(StringIO.new(data)) }.to raise_error(TypeError)
    end

    it 'keeps a NUL byte in a field' do
      expect(ZSV.parse("a\0b,c\n")).to eq([["a\0b", 'c']])
    end
  end

  describe '.parse_line' do
    it 'matches CSV.parse_line' do
      ['a,b', %("x,y",z\n), "a,b\n1,2\n"].each do |line|
        expect(ZSV.parse_line(line)).to eq(CSV.parse_line(line))
      end
      expect(ZSV.parse_line('')).to be_nil
      expect(ZSV.parse_line('a;b', col_sep: ';')).to eq(CSV.parse_line('a;b', col_sep: ';'))
    end
  end

  describe '.parse_enum' do
    it 'enumerates the rows of a String lazily' do
      enum = ZSV.parse_enum(data, headers: true)

      expect(enum).to be_a(Enumerator)
      expect(enum.first).to eq('a' => '1', 'b' => '2')
    end
  end

  describe '.foreach' do
    it 'returns nil with a block, like CSV' do
      with_csv_file(data) do |path|
        expect(ZSV.foreach(path) { |row| row }).to be_nil
      end
    end

    it 'returns an Enumerator without a block' do
      with_csv_file(data) do |path|
        enum = ZSV.foreach(path, headers: true)

        expect(enum).to be_a(Enumerator)
        expect(enum.to_a).to eq(CSV.foreach(path, headers: true).map(&:to_h))
        expect(enum.to_a).to eq(enum.to_a)
      end
    end

    it 'supports each_with_index, with_index and lazy' do
      with_csv_file(data) do |path|
        expect(ZSV.foreach(path).each_with_index.map { |row, index| [index, row.first] })
          .to eq([[0, 'a'], [1, '1'], [2, '3']])
        expect(ZSV.foreach(path).with_index(1).map { |_row, index| index }).to eq([1, 2, 3])
        expect(ZSV.foreach(path).lazy.map(&:first).first(2)).to eq(%w[a 1])
      end
    end

    it 'accepts a Pathname and a read mode, like CSV' do
      with_csv_file(data) do |path|
        expect(ZSV.foreach(Pathname(path), 'r').to_a).to eq(rows)
        expect(ZSV.foreach(path, 'rb', headers: true).to_a).to eq(csv_rows(data, headers: true))
      end
    end

    it 'raises for a missing file' do
      expect { ZSV.foreach('/nonexistent/file.csv') { |row| row } }.to raise_error(Errno::ENOENT)
    end

    it 'closes the file when the block raises' do
      with_csv_file(data) do |path|
        expect { ZSV.foreach(path) { raise 'stop' } }.to raise_error('stop')
      end
    end
  end

  describe '.read' do
    it 'accepts a Pathname' do
      with_csv_file(data) do |path|
        expect(ZSV.read(Pathname(path))).to eq(rows)
      end
    end

    it 'rejects a source that is not a path' do
      expect { ZSV.read(42) }.to raise_error(TypeError)
    end
  end

  describe '.open' do
    it 'rejects write modes with ArgumentError' do
      with_csv_file(data) do |path|
        %w[w a r+ w+].each do |mode|
          expect { ZSV.open(path, mode) }.to raise_error(ArgumentError, /ZSV only reads CSV/)
        end
        expect(File.read(path)).to eq(data)
      end
    end

    it 'accepts read modes and options together' do
      with_csv_file(data) do |path|
        expect(ZSV.open(path, 'r', headers: true, &:read)).to eq(csv_rows(data, headers: true))
        expect(ZSV.open(path, 'rb', &:read)).to eq(rows)
      end
    end

    it 'closes the parser when the block raises' do
      with_csv_file(data) do |path|
        parser = nil
        expect { ZSV.open(path) { |opened| (parser = opened) && raise('stop') } }.to raise_error('stop')
        expect(parser).to be_closed
      end
    end
  end

  describe ZSV::Parser do
    it 'is Enumerable' do
      parser = ZSV.new(data, headers: true)

      expect(parser.map { |row| row['a'] }).to eq(%w[1 3])
    end

    it 'returns itself from #each and #each_row with a block' do
      parser = ZSV.new(data)

      expect(parser.each { |row| row }).to equal(parser)
      expect(parser.each_row { |row| row }).to equal(parser)
    end

    it 'reads a Pathname given to #initialize as a path, not as an IO' do
      with_csv_file(data) do |path|
        parser = ZSV::Parser.allocate
        parser.send(:initialize, Pathname(path))

        expect(parser.read).to eq(rows)
      ensure
        parser&.close
      end
    end

    it 'refuses a second #initialize, even after a failed one' do
      parser = ZSV::Parser.allocate

      expect { parser.send(:initialize, 'missing.csv') }.to raise_error(Errno::ENOENT)
      expect { parser.send(:initialize, data) }.to raise_error(RuntimeError, /already initialized/)
    end

    it 'supports each_with_index, each.with_index and lazy' do
      expect(ZSV.new(data).each_with_index.to_a).to eq(rows.each_with_index.to_a)
      expect(ZSV.new(data).each.with_index(1).map { |_row, index| index }).to eq([1, 2, 3])
      expect(ZSV.new(data).lazy.select { |row| row.first.to_i.positive? }.first(1)).to eq([%w[1 2]])
    end

    it 'continues #each and #read after #shift' do
      parser = ZSV.new(data)

      expect(parser.shift).to eq(%w[a b])
      expect(parser.read).to eq([%w[1 2], %w[3 4]])
      expect(parser.read).to eq([])
      expect(parser.shift).to be_nil
    end

    it 'aliases #to_a to #read' do
      expect(ZSV.new(data).to_a).to eq(rows)
    end

    it 'rewinds a file parser, re-reading the header row' do
      with_csv_file(data) do |path|
        ZSV.open(path, headers: true) do |parser|
          first = parser.read
          parser.rewind

          expect(parser.read).to eq(first)
          expect(first).to eq(csv_rows(data, headers: true))
        end
      end
    end

    it 'rewinds a String parser' do
      parser = ZSV.new(data, headers: %w[x y])
      first = parser.read
      parser.rewind

      expect(parser.read).to eq(first)
    end

    it 'yields nothing once closed' do
      parser = ZSV.new(data)
      parser.close

      expect(parser).to be_closed
      expect(parser.shift).to be_nil
      expect(parser.read).to eq([])
      expect { parser.close }.not_to raise_error
      expect { parser.rewind }.to raise_error(IOError)
    end

    it 'rewinds an IO that can rewind' do
      parser = ZSV.new(StringIO.new(data))
      first = parser.read
      parser.rewind

      expect(parser.read).to eq(first)
    end

    it 'exposes the headers once the first row is read' do
      parser = ZSV.new(data, headers: true)
      parser.shift

      expect(parser.headers).to eq(%w[a b])
      expect(ZSV.new(data, headers: %w[x y]).headers).to eq(%w[x y])
      expect(ZSV.new(data).headers).to be_nil
    end
  end
end
