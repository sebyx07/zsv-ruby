# frozen_string_literal: true

require 'csv'

# Compares ZSV with Ruby's CSV. CSV's answer is brought to ZSV's documented
# row shape first, so that only real divergences fail (docs/API_REFERENCE.md,
# "Differences from CSV"):
#
# * CSV's nil for an empty unquoted field is "" in ZSV, as with CSV's nil_value: ''
# * CSV::Row / CSV::Table are a Hash / an Array of Hash in ZSV
module CSVCompatHelper
  def csv_rows(data, **)
    rows = CSV.parse(data, nil_value: '', **)
    rows.is_a?(CSV::Table) ? rows.map(&:to_h) : rows
  end
end

RSpec.configure do |config|
  config.include CSVCompatHelper
end
