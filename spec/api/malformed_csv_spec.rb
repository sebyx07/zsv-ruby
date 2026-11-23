# frozen_string_literal: true

require_relative 'csv_compat_helper'

RSpec.describe 'ZSV malformed CSV handling' do
  malformed = {
    'a quote inside an unquoted field' => %(a,b"c,d\n),
    'quotes around part of a field' => %(a,b "x" c,d\n),
    'text after a closing quote' => %(a,"b"c,d\n),
    'a space before an opening quote' => %(a, "b",c\n),
    'a space after a closing quote' => %(a,"b" ,c\n),
    'an unclosed quote' => %(a,"b\n1,2\n),
    'an unclosed quote on the last line' => %(a,b\n1,"2),
    'an error on the third line' => %(a,b\n1,2\n3,x"y\n),
    'an error after a multi-line field' => %(a,"b\nc"\n1,x"y\n),
    'an error inside a multi-line record' => %(a,b\n"x\ny"z,1\n),
    'an error in a CRLF file' => %(a,b\r\n1,x"y\r\n)
  }

  describe 'liberal_parsing: false' do
    malformed.each do |name, data|
      it "raises like CSV for #{name}" do
        csv_error = begin
          CSV.parse(data)
        rescue CSV::MalformedCSVError => e
          e
        end

        expect { ZSV.parse(data, liberal_parsing: false) }.to raise_error(ZSV::MalformedCSVError) { |error|
          expect(error.message).to eq(csv_error.message)
          expect(error.line_number).to eq(csv_error.line_number)
          expect(error.lineno).to eq(csv_error.lineno)
        }
      end
    end

    it 'accepts everything CSV accepts' do
      data = %(a,"b ""q"" c",\n"multi\nline","x,y",z\n"",,"end")

      expect(ZSV.parse(data, liberal_parsing: false)).to eq(csv_rows(data))
    end

    it 'honours col_sep' do
      expect(ZSV.parse(%(a;b"c,d\n), col_sep: ',', liberal_parsing: true)).to eq([['a;b"c', 'd']])
      expect { ZSV.parse(%(a;b"c\n), col_sep: ';', liberal_parsing: false) }
        .to raise_error(ZSV::MalformedCSVError, 'Illegal quoting in line 1.')
      expect(ZSV.parse(%(a;"b,c"\n), col_sep: ';', liberal_parsing: false)).to eq([['a', 'b,c']])
    end

    it 'ignores a UTF-8 BOM' do
      expect(ZSV.parse(%(\xEF\xBB\xBF"a",b\n), liberal_parsing: false)).to eq([%w[a b]])
    end

    it 'raises before any row is yielded, from every entry point' do
      with_csv_file(%(a,b\n1,2\n3,x"y\n)) do |path|
        yielded = []
        message = 'Illegal quoting in line 3.'

        expect { ZSV.foreach(path, liberal_parsing: false) { |row| yielded << row } }
          .to raise_error(ZSV::MalformedCSVError, message)
        expect(yielded).to be_empty
        expect { ZSV.read(path, liberal_parsing: false) }.to raise_error(ZSV::MalformedCSVError, message)
        expect { ZSV.open(path, liberal_parsing: false) }.to raise_error(ZSV::MalformedCSVError, message)
        expect { ZSV.new(path, liberal_parsing: false) }.to raise_error(ZSV::MalformedCSVError, message)
        expect { ZSV.new(File.read(path), liberal_parsing: false) }.to raise_error(ZSV::MalformedCSVError, message)
        expect { File.open(path) { |file| ZSV.new(file, liberal_parsing: false) } }
          .to raise_error(ZSV::MalformedCSVError, message)
        expect { ZSV.foreach(path, liberal_parsing: false).to_a }.to raise_error(ZSV::MalformedCSVError, message)
      end
    end

    it 'raises InvalidEncodingError for bytes invalid in the encoding, like CSV' do
      data = "a,b\n1,\xFF\n"

      expect { CSV.parse(data) }.to raise_error(CSV::InvalidEncodingError, 'Invalid byte sequence in UTF-8 in line 2.')
      expect { ZSV.parse(data, liberal_parsing: false) }.to raise_error(ZSV::InvalidEncodingError) { |error|
        expect(error.message).to eq('Invalid byte sequence in UTF-8 in line 2.')
        expect(error.line_number).to eq(2)
      }
    end

    it 'checks a file against the encoding option' do
      with_csv_file("a,b\n1,caf\xE9\n".b) do |path|
        expect { ZSV.read(path, liberal_parsing: false) }
          .to raise_error(ZSV::InvalidEncodingError, 'Invalid byte sequence in UTF-8 in line 2.')
        expect(ZSV.read(path, liberal_parsing: false, encoding: 'ISO-8859-1').last.last.bytes).to eq("caf\xE9".bytes)
      end
    end
  end

  describe 'the default, lenient mode' do
    it 'never raises for the inputs CSV rejects' do
      malformed.each_value do |data|
        expect { ZSV.parse(data) }.not_to raise_error
        expect { ZSV.parse(data, liberal_parsing: true) }.not_to raise_error
      end
    end

    it 'keeps a quote inside an unquoted field, like CSV liberal_parsing' do
      [%(a,b"c,d\n), %(a,b "x" c,d\n), %(a, "b",c\n)].each do |data|
        expect(ZSV.parse(data)).to eq(CSV.parse(data, liberal_parsing: true))
      end
    end

    it 'drops the quotes of a field with text after its closing quote, unlike CSV liberal_parsing' do
      data = %(a,"b"c,d\n)

      expect(CSV.parse(data, liberal_parsing: true)).to eq([['a', '"b"c', 'd']])
      expect(ZSV.parse(data)).to eq([%w[a bc d]])
    end

    it 'reads an unclosed quoted field to the end of the input' do
      rows = ZSV.parse(%(x,y\na,"b\n1,2\n))

      expect(rows.first).to eq(%w[x y])
      expect(rows.last.first).to eq('a')
      expect(rows.last.last).to start_with("b\n1,2")
    end
  end

  describe 'error classes' do
    it 'mirrors the CSV hierarchy under ZSV::Error' do
      expect(ZSV::Error).to be < StandardError
      expect(ZSV::MalformedCSVError).to be < ZSV::Error
      expect(ZSV::InvalidEncodingError).to be < ZSV::Error
    end

    it 'builds messages without a line number' do
      error = ZSV::MalformedCSVError.new('CSV parsing error')

      expect(error.message).to eq('CSV parsing error')
      expect(error.line_number).to be_nil
    end
  end
end
