# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/xlsx_helper'
require_relative '../../web/xlsx_converter'

RSpec.describe XlsxConverter do
  include XlsxHelper

  it 'converts the first sheet of an xlsx into a csv with the same rows' do
    xlsx = write_xlsx([%w[Sequence Address], ['1', 'Rua A, 10'], ['2', 'Rua B, 20']])
    csv_path = File.join(Dir.mktmpdir, 'out.csv')

    XlsxConverter.convert(xlsx, csv_path)

    rows = CSV.read(csv_path)
    expect(rows).to eq([%w[Sequence Address], ['1', 'Rua A, 10'], ['2', 'Rua B, 20']])
  end
end
