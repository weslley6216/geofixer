# frozen_string_literal: true

require 'date'
require_relative 'xlsx_converter'
require_relative '../app/address_processor'

# Runs one upload to completion: convert the xlsx, then process it with the
# Phase 1 core. Returns [csv_path, log_path] of the generated results.
class JobRunner
  def initialize(output_label: ENV.fetch('OUTPUT_LABEL', 'Andreia Eslava'))
    @output_label = output_label
  end

  def run(dir, &on_progress)
    csv_path = File.join(dir, 'input.csv')
    XlsxConverter.convert(File.join(dir, 'input.xlsx'), csv_path)

    date = Date.today.strftime('%d-%m-%Y')
    output_csv = File.join(dir, "#{date} #{@output_label}.csv")
    output_log = File.join(dir, "#{date} log_enderecos.txt")

    AddressProcessor.new(csv_path, output_csv, output_log, on_progress: on_progress).process_file
    [output_csv, output_log]
  end
end
