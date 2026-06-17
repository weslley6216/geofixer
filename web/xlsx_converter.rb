# frozen_string_literal: true

require 'roo'
require 'csv'

# Converts the first sheet of an .xlsx file into a UTF-8 .csv that
# AddressProcessor can read. Extracted from the old Main orchestrator.
class XlsxConverter
  def self.convert(xlsx_path, csv_path)
    xlsx = Roo::Spreadsheet.open(xlsx_path)
    CSV.open(csv_path, 'w', encoding: 'UTF-8') do |csv|
      xlsx.sheet(0).each_row_streaming { |row| csv << row.map(&:value) }
    end
    csv_path
  end
end
