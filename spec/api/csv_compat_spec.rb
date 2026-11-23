# frozen_string_literal: true

require_relative 'csv_compat_helper'
require 'stringio'

RSpec.describe 'ZSV compatibility with CSV' do
  inputs = {
    'plain rows' => "a,b,c\n1,2,3\n4,5,6\n",
    'an empty input' => '',
    'no trailing newline' => "a,b\n1,2",
    'a single row without a newline' => 'a,b',
    'a single field' => 'a',
    'a quoted separator' => %(a,"b,c",d\n),
    'escaped quotes' => %(a,"b ""q"" c",d\n),
    'a field of one escaped quote' => %(a,"""",d\n),
    'an embedded LF' => %(a,"b\nc",d\n1,2,3\n),
    'an embedded CRLF' => %(a,"b\r\nc"\r\n1,2\r\n),
    'CRLF line endings' => "a,b\r\n1,2\r\n",
    'CR line endings' => "a,b\r1,2\r",
    'empty unquoted and quoted fields' => %(a,,"",d\n),
    'a row of empty fields' => ",,\na,b,c\n",
    'a trailing delimiter' => "a,b,\n1,2,\n",
    'a leading delimiter' => ",a,b\n,1,2\n",
    'a blank line in the middle' => "a,b\n\n1,2\n",
    'a blank line at the end' => "a,b\n1,2\n\n",
    'blank lines at the start' => "\n\na,b\n",
    'only a newline' => "\n",
    'a quoted empty line' => %(a\n""\nb\n),
    'whitespace as data' => "a , b\n 1,2 \n",
    'ragged rows' => "a,b,c\n1\n1,2,3,4\n",
    'non-ASCII text' => "näme,värde\nå,日本\n",
    'a quoted field at the end of the input' => %(a,"b"),
    'a NUL byte' => "a\0b,c\n",
    'a field longer than a row buffer chunk' => "a,#{'x' * 50_000},c\n1,2,3\n",
    'many columns' => "#{(1..1000).to_a.join(',')}\n"
  }

  # Every way to get rows out of ZSV; they take different routes through the C.
  def zsv_rows_by_entry_point(data, **options)
    rows = {
      'ZSV.parse' => ZSV.parse(data, **options),
      'Parser.from_string' => ZSV::Parser.from_string(data, **options).read,
      'ZSV.new(io)' => ZSV.new(StringIO.new(data), **options).read
    }
    with_csv_file(data) do |path|
      rows['ZSV.read'] = ZSV.read(path, **options)
      rows['ZSV.foreach'] = ZSV.foreach(path, **options).to_a
      rows['ZSV.open'] = ZSV.open(path, **options, &:read)
      rows['Parser#shift'] = ZSV.open(path, **options) do |parser|
        shifted = []
        while (row = parser.shift)
          shifted << row
        end
        shifted
      end
    end
    rows
  end

  def expect_parity(data, **options)
    expected = csv_rows(data, **options)

    zsv_rows_by_entry_point(data, **options).each do |entry_point, rows|
      expect(rows).to eq(expected), "#{entry_point} returned #{rows.inspect[0, 300]}, CSV #{expected.inspect[0, 300]}"
    end
  end

  describe 'rows as Arrays' do
    inputs.each do |name, data|
      it "matches CSV for #{name}" do
        expect_parity(data)
      end
    end

    it 'does not modify the given string' do
      data = +'a,b'
      ZSV.parse(data)

      expect(data).to eq('a,b')
      expect(data).not_to be_frozen
    end
  end

  describe 'col_sep' do
    { "\t" => "a\tb\n1\t\"x\ty\"\n\t\n", ';' => "a;b\n1;\"x;y\"\n", '|' => "a|b,c\n1|2\n" }.each do |col_sep, data|
      it "matches CSV for #{col_sep.inspect}" do
        expect_parity(data, col_sep: col_sep)
      end
    end
  end

  describe 'row_sep' do
    it 'auto-detects line endings like CSV' do
      ["a,b\n1,2\n", "a,b\r\n1,2\r\n", "a,b\r1,2\r"].each do |data|
        expect_parity(data, row_sep: :auto)
      end
    end

    it 'accepts the standard line endings explicitly' do
      expect_parity("a,b\r\n1,2\r\n", row_sep: "\r\n")
      expect_parity("a,b\n1,2\n", row_sep: "\n")
      expect_parity("a,b\r1,2\r", row_sep: "\r")
    end
  end

  describe 'headers: true' do
    {
      'plain rows' => "name,age\nAlice,30\nBob,25\n",
      'quoted headers' => %("first name","a,b"\nAlice,1\n),
      'a header row only' => "a,b\n",
      'an empty input' => '',
      'empty values' => %(a,b\n1,\n,""\n),
      'CRLF line endings' => "a,b\r\n1,2\r\n",
      'no trailing newline' => "a,b\n1,2",
      'duplicate headers' => "a,a,b\n1,2,3\n",
      'an empty header' => "a,,b\n1,2,3\n",
      'a short row' => "a,b,c\n1,2\n",
      'a blank line between rows' => "a,b\n\n1,2\n",
      'non-ASCII headers' => "näme,värde\nå,日本\n"
    }.each do |name, data|
      it "matches CSV for #{name}" do
        expect_parity(data, headers: true)
      end
    end

    it 'accepts :first_row like CSV' do
      expect_parity("a,b\n1,2\n", headers: :first_row)
    end

    it 'returns Hashes with String keys' do
      row = ZSV.parse("a,b\n1,2\n", headers: true).first

      expect(row).to be_a(Hash)
      expect(row.keys).to eq(%w[a b])
    end

    it 'matches CSV.foreach and CSV.read' do
      with_csv_file("name,age\nAlice,30\nBob,25\n") do |path|
        expected = CSV.foreach(path, headers: true).map(&:to_h)

        expect(ZSV.foreach(path, headers: true).to_a).to eq(expected)
        expect(ZSV.read(path, headers: true)).to eq(CSV.read(path, headers: true).map(&:to_h))
      end
    end
  end

  describe 'headers given by the caller' do
    it 'matches CSV for an Array, keeping the first row as data' do
      expect_parity("1,2\n3,4\n", headers: %w[x y])
    end

    it 'matches CSV for a short row and duplicate names' do
      expect_parity("1\n3,4\n", headers: %w[x y])
      expect_parity("1,2,3\n", headers: %w[x x y])
    end

    it 'matches CSV for headers given as a CSV line' do
      expect_parity("1,2\n3,4\n", headers: 'x,y')
      expect_parity("1;2\n", headers: 'x;"y;z"', col_sep: ';')
    end
  end

  # docs/API_REFERENCE.md, "Differences from CSV"
  describe 'documented differences from CSV' do
    it 'returns "" where CSV returns nil for an empty unquoted field' do
      expect(CSV.parse("a,,b\n")).to eq([['a', nil, 'b']])
      expect(ZSV.parse("a,,b\n")).to eq([['a', '', 'b']])
      expect(ZSV.parse("a,b\n1,\n", headers: true)).to eq([{ 'a' => '1', 'b' => '' }])
    end

    it 'strips a UTF-8 BOM, which CSV only does with encoding: "bom|utf-8"' do
      data = "\xEF\xBB\xBFa,b\n1,2\n"

      expect(CSV.parse(data).first.first).to eq("\xEF\xBB\xBFa")
      expect(zsv_rows_by_entry_point(data).values).to all(eq([%w[a b], %w[1 2]]))
    end

    it 'keys the fields beyond the headers by their index, where CSV keys them all by nil' do
      data = "a,b\n1,2,3,4\n"

      expect(CSV.parse(data, headers: true).first.to_h).to eq('a' => '1', 'b' => '2', nil => '3')
      expect(ZSV.parse(data, headers: true)).to eq([{ 'a' => '1', 'b' => '2', 2 => '3', 3 => '4' }])
    end

    it 'returns frozen Strings in plain Arrays and Hashes' do
      rows = ZSV.parse("a,b\n1,2\n")
      hashes = ZSV.parse("a,b\n1,2\n", headers: true)

      expect(rows).to be_an_instance_of(Array)
      expect(rows.first).to be_an_instance_of(Array)
      expect(hashes.first).to be_an_instance_of(Hash)
      expect(rows.flatten + hashes.first.keys + hashes.first.values).to all(be_frozen)
    end

    it 'reads each line ending on its own, where CSV settles on the first one and rejects the others' do
      data = "a\r\nb\nc\n"

      expect { CSV.parse(data) }.to raise_error(CSV::MalformedCSVError, /Unquoted fields do not allow new line/)
      expect(ZSV.parse(data)).to eq([['a'], ['b'], ['c']])
    end

    it 'limits a row to max_row_size bytes and max_columns fields, which CSV does not' do
      wide = "#{(1..2000).to_a.join(',')}\n"
      long = "a,#{'x' * 600_000}\nb,c\n"

      expect { ZSV.parse(wide) }.to raise_error(ZSV::MalformedCSVError, /max_columns/)
      expect(ZSV.parse(wide, max_columns: 2000)).to eq(CSV.parse(wide))
      expect(ZSV.parse(long, max_row_size: 1_000_000)).to eq(CSV.parse(long))
    end
  end

  describe 'input larger than one read buffer' do
    it 'parses a file with many rows like CSV' do
      data = Array.new(60_000) { |i| "#{i},name #{i},\"quoted, #{i}\"" }.join("\n")

      with_csv_file(data) do |path|
        expect(ZSV.read(path)).to eq(CSV.read(path))
        expect(ZSV.read(path, buffer_size: 4096)).to eq(CSV.read(path))
      end
    end
  end
end
