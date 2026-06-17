# frozen_string_literal: true

require 'axlsx'
require 'tmpdir'

module XlsxHelper
  # Writes an .xlsx with the given rows (array of arrays) and returns its path.
  def write_xlsx(rows, path = File.join(Dir.mktmpdir, 'sample.xlsx'))
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: 'Sheet1') do |sheet|
      rows.each { |row| sheet.add_row(row) }
    end
    package.serialize(path)
    path
  end
end
