# frozen_string_literal: true

require_relative './app/services/google_drive/downloader_service'
require_relative './app/services/google_drive/uploader_service'
require_relative './app/address_processor'
require_relative './app/utils/logger'
require 'roo'
require 'csv'
require 'date'
require 'fileutils'
require 'dotenv/load'

class Main
  SOURCE_FOLDER_ID = ENV['SOURCE_FOLDER_ID']
  DESTINATION_FOLDER_ID = ENV['DESTINATION_FOLDER_ID']
  LAST_CHECKED_FILE = ENV['LAST_CHECKED_FILE']
  XLSX_MIME_TYPE = ENV['XLSX_MIME_TYPE']

  def initialize
    @logger = Utils::Logger
    @downloader = GoogleDrive::DownloaderService.new
    @uploader = GoogleDrive::UploaderService.new
  end

  def run
    log_header('STARTING FILE PROCESSING')

    print_last_checked_time
    files = fetch_new_files

    return log_warning('No new files to process') if files.empty?

    process_files(files)
    update_last_checked_time

    log_success('Processing completed successfully!')
  end

  private

  def print_last_checked_time
    last_checked = load_last_checked_time
    log_step("⏱️ Last check: #{format_time(last_checked)}")
  end

  def fetch_new_files
    log_step('📡 Connecting to Google Drive...')
    xlsx_files = @downloader.files_in_folder(SOURCE_FOLDER_ID, mime_type: XLSX_MIME_TYPE)
    log_step("📄 Found #{xlsx_files.size} XLSX files")

    new_files = xlsx_files.select { |f| f.modified_time.to_time > load_last_checked_time }
    log_step("🆕 New files for processing: #{new_files.size}")

    new_files
  end

  def process_files(files)
    files.each_with_index do |file, index|
      log_step("🔧 Processing #{index + 1}/#{files.size}: #{file.name}")
      process_file(file)
    end
  end

  def process_file(file)
    file_path = "files/#{file.name}"
    @downloader.download(file.id, file_path)

    csv_path = 'files/arquivo.csv'
    convert_xlsx_to_csv(file_path, csv_path)

    date_today = Date.today.strftime('%d-%m-%Y')
    output_file = "files/#{date_today} Andreia Eslava.csv"
    log_file = "files/#{date_today} log_enderecos.txt"

    processor = AddressProcessor.new(csv_path, output_file, log_file)
    processor.process_file

    upload_results(date_today)
    cleanup_files(file_path, csv_path)
  end

  def convert_xlsx_to_csv(xlsx_path, csv_path)
    xlsx = Roo::Spreadsheet.open(xlsx_path)
    CSV.open(csv_path, 'wb') { |csv| xlsx.sheet(0).each_row_streaming { |row| csv << row.map(&:value) } }
  end

  def upload_results(date_today)
    output_files = {
      '📊 CSV file' => "files/#{date_today} Andreia Eslava.csv",
      '📝 Log file' => "files/#{date_today} log_enderecos.txt"
    }

    output_files.each do |desc, path|
      return log_warning("⚠️ #{desc} not found: #{path}") unless File.exist?(path)

      log_step("⬆️ Uploading #{desc} to Google Drive...")
      @uploader.upload(path, DESTINATION_FOLDER_ID)
      File.delete(path)
      log_step("✔️ #{desc} sent and removed locally")
    end
  end

  def cleanup_files(original_path, csv_path)
    File.delete(original_path)
    log_step("🗑️ Original file removed: #{original_path}")

    return unless File.exist?(csv_path)

    File.delete(csv_path)
    log_step('🗑️ Temporary CSV file removed')
  end

  def load_last_checked_time
    return Time.at(0) unless File.exist?(LAST_CHECKED_FILE)

    Time.parse(File.read(LAST_CHECKED_FILE).chomp)
  end

  def update_last_checked_time
    File.write(LAST_CHECKED_FILE, Time.now.to_s)
    log_step('🕰️ Updated last check time')
  end

  def log_step(message) = @logger.info(message)

  def log_header(message)
    @logger.info('=' * 70)
    @logger.info("  #{message.upcase}")
    @logger.info('=' * 70)
  end

  def log_success(message) = @logger.info("✅ #{message}")
  def log_warning(message) = @logger.warn("⚠️ #{message}")
  def log_error(message) = @logger.error("❌ #{message}")
  def format_time(time) = time.strftime('%d/%m/%Y %H:%M:%S')
end

begin
  logger = Utils::Logger
  logger.info('=' * 70)
  logger.info('ADDRESS PROCESSOR - START OF EXECUTION')
  logger.info('=' * 70)

  Main.new.run

  logger.info('=' * 70)
  logger.info('Processing completed')
  logger.info('=' * 70)
rescue StandardError => e
  logger.error("\n💥 FATAL ERROR: #{e.message}")
  logger.error('Backtrace:')
  logger.error(e.backtrace.first(5).join("\n"))
  logger.info('=' * 70)
  exit 1
end
