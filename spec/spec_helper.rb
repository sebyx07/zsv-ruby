# frozen_string_literal: true

require 'zsv'
require 'tmpdir'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Helper to create temporary CSV files
module CSVHelpers
  # Yields the path of a file holding +content+ (written as bytes), removed
  # with its directory when the block returns. A directory rather than a
  # Tempfile: a Tempfile nothing references is unlinked whenever GC collects
  # it, which can be in the middle of the example.
  def with_csv_file(content)
    Dir.mktmpdir('zsv-spec') do |dir|
      path = File.join(dir, 'test.csv')
      File.binwrite(path, content)
      yield path
    end
  end
end

RSpec.configure do |config|
  config.include CSVHelpers
end
