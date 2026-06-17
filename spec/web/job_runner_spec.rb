# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../support/xlsx_helper'
require_relative '../../web/job_runner'

RSpec.describe JobRunner do
  include XlsxHelper

  it 'converts the upload and runs AddressProcessor, returning the csv and log paths' do
    dir = Dir.mktmpdir
    write_xlsx([%w[Sequence Address], ['1', 'Rua A, 10']], File.join(dir, 'input.xlsx'))

    fake_processor = instance_double(AddressProcessor, process_file: nil)
    expect(AddressProcessor).to receive(:new) do |input, output_csv, output_log, **|
      expect(input).to eq(File.join(dir, 'input.csv'))
      expect(output_csv).to match(%r{/\d{2}-\d{2}-\d{4} Andreia Eslava\.csv$})
      expect(output_log).to match(%r{/\d{2}-\d{2}-\d{4} log_enderecos\.txt$})
      fake_processor
    end

    csv_path, log_path = described_class.new.run(dir)

    expect(File.exist?(File.join(dir, 'input.csv'))).to be true
    expect(csv_path).to end_with('Andreia Eslava.csv')
    expect(log_path).to end_with('log_enderecos.txt')
  end
end
