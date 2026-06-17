# frozen_string_literal: true

require 'csv'
require_relative './services/address_normalizer_service'
require_relative './services/zip_code_service'
require_relative './services/google_geocoding_service'
require_relative './services/log_generator_service'
require_relative '../app/utils/logger'
require_relative '../app/utils/i18n'
require_relative '../app/utils/cache_manager'

class AddressProcessor
  ADDRESS_COLUMN = 'Destination Address'
  COMPLEMENT_COLUMN = 'Complement'
  ZIP_CODE_COLUMN = 'Zipcode/Postal code'
  NEIGHBORHOOD_COLUMN = 'Bairro'
  CITY_COLUMN = 'City'
  SEQUENCE_COLUMN = 'Sequence'
  STOP_COLUMN = 'Stop'
  LATITUDE_COLUMN = 'Latitude'
  LONGITUDE_COLUMN = 'Longitude'
  NUMERIC_COLUMNS = [SEQUENCE_COLUMN, STOP_COLUMN].freeze
  CSV_ENCODING = 'bom|utf-8'

  def initialize(input_file, output_file, log_file)
    @input_file = input_file
    @output_file = output_file
    @log_file = log_file
  end

  def process_file
    Utils::Logger.info("Starting file processing: #{@input_file}")

    address_count = Hash.new { |h, k| h[k] = { count: 0, sequences: [] } }
    street_count  = Hash.new { |h, k| h[k] = { count: 0, sequences: [] } }

    CSV.open(@output_file, 'w:UTF-8', col_sep: ',') do |csv|
      new_headers = build_headers
      csv << new_headers
      Utils::Logger.info('Header processed and written to output file.')

      CSV.foreach(@input_file, headers: true, col_sep: ',', encoding: CSV_ENCODING) do |row|
        next unless row[ZIP_CODE_COLUMN]

        processed_row = process_row(row.to_hash)
        next unless processed_row

        update_counts(processed_row, address_count, street_count)
        write_row_to_csv(processed_row, csv, new_headers)
      end
    end

    generate_and_save_logs(address_count, street_count)
    Utils::Logger.info("Processing completed. File saved as: #{@output_file.split('/').last}")
    Utils::Logger.info("Geolocation cache was used #{Utils::CacheManager.location_cache_hits} times and the zip code cache was used #{Utils::CacheManager.zip_code_cache_hits} times")
    Utils::CacheManager.clear!
  end

  private

  def build_headers
    headers = CSV.open(@input_file, 'r', col_sep: ',', encoding: CSV_ENCODING, &:first)
    headers.insert(headers.index(ADDRESS_COLUMN) + 1, COMPLEMENT_COLUMN)
  end

  def normalize_for_cache(*address_parts)
    address_parts.map { |part| I18n.transliterate(part.to_s.downcase).gsub(/[^a-z0-9]/, '_') }.join('_')
  end

  def fetch_street_name_from_zip_code(zip_code)
    Utils::CacheManager.fetch_zip_code(zip_code) ||
      ZipCodeService.fetch_street_name_from_zip_code(zip_code).tap do |zip_code_info|
        Utils::CacheManager.store_zip_code(zip_code, zip_code_info) if zip_code_info
      end
  end

  def fetch_location(street_name, house_number, zip_code, neighborhood, city)
    cache_key = normalize_for_cache(street_name, house_number, zip_code, neighborhood, city)

    Utils::CacheManager.fetch_location(cache_key) ||
      GoogleGeocodingService.new
                            .fetch_location_from_google(street_name, house_number, neighborhood, city)
                            .tap { |location| Utils::CacheManager.store_location(cache_key, location) if location }
  end

  def process_row(row)
    zip_code = row[ZIP_CODE_COLUMN]&.gsub('-', '')
    return unless zip_code

    Utils::Logger.info("Processing zip code: #{zip_code}")
    zip_code_info = fetch_street_name_from_zip_code(zip_code)

    if zip_code_info
      row[ADDRESS_COLUMN] = corrected_address(row[ADDRESS_COLUMN], zip_code_info)
    else
      Utils::Logger.warn("Zip code not found: #{zip_code}")
    end

    geocode_address(row, row[ADDRESS_COLUMN], zip_code, row[NEIGHBORHOOD_COLUMN], row[CITY_COLUMN])
    row.tap { update_row_complement(row) }
  end

  def corrected_address(address, zip_code_info)
    Utils::Logger.info("Address found: #{zip_code_info[:street_name]}")
    input_street = street_part(address)

    if AddressNormalizerService.new(input_street).street_name_matches?(zip_code_info[:street_name])
      replace_street(address, zip_code_info[:street_name])
    else
      address_from_street_search(address, input_street, zip_code_info)
    end
  end

  def address_from_street_search(address, input_street, zip_code_info)
    Utils::Logger.warn("Trying to correct street name: #{input_street}")
    street_info = ZipCodeService.fetch_zip_code_by_street_name(input_street, zip_code_info[:city], zip_code_info[:uf])
    street_info = street_info.first if street_info.is_a?(Array)
    logradouro = street_info&.dig('logradouro')

    logradouro ? replace_street(address, logradouro) : address
  end

  def street_part(address) = address.split(',', 2).first&.strip
  def replace_street(address, new_street) = "#{new_street},#{address.split(',', 2).last}"

  def geocode_address(row, full_address, zip_code, neighborhood, city)
    street_name, house_number = extract_street_and_number(full_address)
    return unless street_name && house_number

    location = fetch_location(street_name, house_number, zip_code, neighborhood, city)
    return unless location

    update_row_with_location(row, location)
  end

  def extract_street_and_number(full_address)
    parts = full_address.split(',')
    street_name = parts.first&.strip
    house_number = parts[1]&.strip&.split&.first
    [street_name, house_number]
  end

  def update_row_with_location(row, location)
    row[LATITUDE_COLUMN] = location['lat'].to_s
    row[LONGITUDE_COLUMN] = location['lng'].to_s
  end

  def update_row_complement(row)
    normalizer = AddressNormalizerService.new(row[ADDRESS_COLUMN])
    main, complement = normalizer.separate_complement
    row[ADDRESS_COLUMN] = main
    row[COMPLEMENT_COLUMN] = complement ? complement.gsub(/^,\s*/, '') : ''
  end

  def update_counts(row, address_count, street_count)
    sequence = row[SEQUENCE_COLUMN].to_i
    address = row[ADDRESS_COLUMN]
    street = address.split(',').first

    address_count[address][:count] += 1
    address_count[address][:sequences] << sequence

    street_count[street][:count] += 1
    street_count[street][:sequences] << sequence
  end

  def write_row_to_csv(row, csv, headers)
    csv << headers.map do |header|
      NUMERIC_COLUMNS.include?(header) ? row[header].to_s.split('.').first.to_i : row[header]
    end
  end

  def generate_and_save_logs(address_count, street_count)
    address_logs = LogGeneratorService.generate_top_items_log(address_count, 'Endereços', 10)
    street_logs  = LogGeneratorService.generate_top_items_log(street_count, 'Ruas', 10)
    travessa_logs = LogGeneratorService.generate_top_items_log(
      street_count.select { |street, _| street =~ /\A(Travessa|Passagem)/ },
      'Travessas e/ou Passagens', 10
    )

    LogGeneratorService.save_logs_to_file(@log_file, address_logs, street_logs, travessa_logs)
  end
end
