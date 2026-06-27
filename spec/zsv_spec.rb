# frozen_string_literal: true

RSpec.describe ZSV do
  it 'has a version number' do
    expect(ZSV::VERSION).not_to be nil
    expect(ZSV::VERSION).to eq('1.4.3')
  end

  describe '.parse' do
    it 'parses simple CSV string' do
      csv = "a,b,c\n1,2,3\n4,5,6\n"
      rows = ZSV.parse(csv)

      expect(rows).to eq([
                           %w[a b c],
                           %w[1 2 3],
                           %w[4 5 6]
                         ])
    end

    it 'parses empty CSV' do
      expect(ZSV.parse('')).to eq([])
    end

    it 'handles quoted fields' do
      csv = "a,\"b,c\",d\n"
      rows = ZSV.parse(csv)

      expect(rows).to eq([['a', 'b,c', 'd']])
    end

    it 'handles newlines in quoted fields' do
      csv = "a,\"b\nc\",d\n"
      rows = ZSV.parse(csv)

      expect(rows).to eq([%W[a b\nc d]])
    end

    context 'with headers option' do
      it 'returns array of hashes' do
        csv = "name,age\nAlice,30\nBob,25\n"
        rows = ZSV.parse(csv, headers: true)

        expect(rows).to eq([
                             { 'name' => 'Alice', 'age' => '30' },
                             { 'name' => 'Bob', 'age' => '25' }
                           ])
      end

      it 'handles custom headers' do
        csv = "Alice,30\nBob,25\n"
        rows = ZSV.parse(csv, headers: %w[name age])

        expect(rows).to eq([
                             { 'name' => 'Alice', 'age' => '30' },
                             { 'name' => 'Bob', 'age' => '25' }
                           ])
      end
    end

    context 'with custom delimiter' do
      it 'parses tab-separated values' do
        csv = "a\tb\tc\n1\t2\t3\n"
        rows = ZSV.parse(csv, col_sep: "\t")

        expect(rows).to eq([
                             %w[a b c],
                             %w[1 2 3]
                           ])
      end

      it 'parses pipe-separated values' do
        csv = "a|b|c\n1|2|3\n"
        rows = ZSV.parse(csv, col_sep: '|')

        expect(rows).to eq([
                             %w[a b c],
                             %w[1 2 3]
                           ])
      end
    end
  end

  describe '.foreach' do
    it 'yields each row' do
      with_csv_file("a,b\n1,2\n3,4\n") do |path|
        rows = []
        ZSV.foreach(path) { |row| rows << row }

        expect(rows).to eq([
                             %w[a b],
                             %w[1 2],
                             %w[3 4]
                           ])
      end
    end

    it 'returns enumerator without block' do
      with_csv_file("a,b\n1,2\n") do |path|
        enum = ZSV.foreach(path)
        expect(enum).to be_a(Enumerator)
        expect(enum.first).to eq(%w[a b])
      end
    end

    it 'handles large files efficiently' do
      with_csv_file(1000.times.map { |i| "#{i},value#{i}" }.join("\n")) do |path|
        count = 0
        ZSV.foreach(path) { count += 1 }

        expect(count).to eq(1000)
      end
    end

    context 'with headers' do
      it 'yields hashes' do
        with_csv_file("name,value\nfoo,1\nbar,2\n") do |path|
          rows = []
          ZSV.foreach(path, headers: true) { |row| rows << row }

          expect(rows).to eq([
                               { 'name' => 'foo', 'value' => '1' },
                               { 'name' => 'bar', 'value' => '2' }
                             ])
        end
      end
    end
  end

  describe '.read' do
    it 'reads entire file into array' do
      with_csv_file("a,b\n1,2\n3,4\n") do |path|
        rows = ZSV.read(path)

        expect(rows).to eq([
                             %w[a b],
                             %w[1 2],
                             %w[3 4]
                           ])
      end
    end

    it 'works with headers' do
      with_csv_file("x,y\n1,2\n3,4\n") do |path|
        rows = ZSV.read(path, headers: true)

        expect(rows).to eq([
                             { 'x' => '1', 'y' => '2' },
                             { 'x' => '3', 'y' => '4' }
                           ])
      end
    end
  end

  describe '.open' do
    it 'returns parser instance' do
      with_csv_file("a,b\n1,2\n") do |path|
        parser = ZSV.open(path)

        expect(parser).to be_a(ZSV::Parser)
        expect(parser.shift).to eq(%w[a b])

        parser.close
      end
    end

    it 'yields parser to block and auto-closes' do
      with_csv_file("a,b\n1,2\n") do |path|
        rows = []
        result = ZSV.open(path) do |parser|
          parser.each { |row| rows << row }
          'done'
        end

        expect(rows).to eq([%w[a b], %w[1 2]])
        expect(result).to eq('done')
      end
    end
  end

  describe ZSV::Parser do
    describe '#shift' do
      it 'returns next row' do
        parser = ZSV::Parser.new("a,b\n1,2\n3,4\n")

        expect(parser.shift).to eq(%w[a b])
        expect(parser.shift).to eq(%w[1 2])
        expect(parser.shift).to eq(%w[3 4])
        expect(parser.shift).to be_nil
      end
    end

    describe '#each' do
      it 'iterates all rows' do
        parser = ZSV::Parser.new("a\nb\nc\n")
        rows = parser.map { |row| row }

        expect(rows).to eq([['a'], ['b'], ['c']])
      end

      it 'returns enumerator without block' do
        parser = ZSV::Parser.new("a\nb\n")
        enum = parser.each

        expect(enum).to be_a(Enumerator)
        expect(enum.to_a).to eq([['a'], ['b']])
      end
    end

    describe '#rewind' do
      it 'resets parser to beginning' do
        with_csv_file("a\nb\nc\n") do |path|
          parser = ZSV::Parser.new(path)

          expect(parser.shift).to eq(['a'])
          expect(parser.shift).to eq(['b'])

          parser.rewind

          expect(parser.shift).to eq(['a'])
          expect(parser.shift).to eq(['b'])

          parser.close
        end
      end
    end

    describe '#headers' do
      it 'returns headers when enabled' do
        parser = ZSV::Parser.new("x,y\n1,2\n", headers: true)

        parser.shift # Process first data row
        expect(parser.headers).to eq(%w[x y])
      end

      it 'returns custom headers' do
        parser = ZSV::Parser.new("1,2\n", headers: %w[a b])

        expect(parser.headers).to eq(%w[a b])
      end

      it 'returns nil without headers' do
        parser = ZSV::Parser.new("a,b\n")

        expect(parser.headers).to be_nil
      end
    end

    describe '#closed?' do
      it 'returns false for open parser' do
        parser = ZSV::Parser.new("a\n")
        expect(parser.closed?).to be false
      end

      it 'returns true after closing' do
        parser = ZSV::Parser.new("a\n")
        parser.close

        expect(parser.closed?).to be true
      end
    end

    describe '#read' do
      it 'returns all rows as array' do
        parser = ZSV::Parser.new("a,b\n1,2\n3,4\n")
        rows = parser.read

        expect(rows).to eq([
                             %w[a b],
                             %w[1 2],
                             %w[3 4]
                           ])
      end
    end
  end

  describe 'error handling' do
    it 'defines error classes' do
      expect(ZSV::Error).to be < StandardError
      expect(ZSV::MalformedCSVError).to be < ZSV::Error
      expect(ZSV::InvalidEncodingError).to be < ZSV::Error
    end
  end
end
