# frozen_string_literal: true

module ZSV
  # Raised for malformed CSV, mirroring CSV::MalformedCSVError: the message
  # ends with "in line N." and the line is available as #line_number.
  #
  # ZSV parses leniently by default; this error is raised for quoting
  # problems only when +liberal_parsing: false+ is given.
  class MalformedCSVError < Error
    # @return [Integer, nil] 1-based number of the offending record, as in CSV
    attr_reader :line_number
    alias lineno line_number

    def initialize(message = nil, line_number = nil)
      @line_number = line_number
      super(line_number ? "#{message} in line #{line_number}." : message)
    end
  end

  # Raised by strict parsing (+liberal_parsing: false+) when the input is not
  # valid in its encoding, mirroring CSV::InvalidEncodingError.
  class InvalidEncodingError < Error
    # @return [Integer, nil] 1-based number of the offending record, as in CSV
    attr_reader :line_number
    alias lineno line_number

    def initialize(message = nil, line_number = nil)
      @line_number = line_number
      super(line_number ? "#{message} in line #{line_number}." : message)
    end
  end
end
