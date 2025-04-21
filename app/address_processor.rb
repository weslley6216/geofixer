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
  def initialize(input_file, output_file, log_file)
    @input_file = input_file
    @output_file = output_file
    @log_file = log_file
    @zip_code_cache = {}
  end

  def process_file
    Utils::Logger.info("Starting file processing: #{@input_file}")

    address_count = Hash.new { |h, k| h[k] = { count: 0, sequences: [] } }
    street_count  = Hash.new { |h, k| h[k] = { count: 0, sequences: [] } }

    CSV.open(@output_file, 'w', col_sep: ',') do |csv|
      headers = CSV.open(@input_file, 'r', col_sep: ',', &:first)
      new_headers = headers.insert(headers.index('Destination Address') + 1, 'Complement')
      csv << new_headers
      Utils::Logger.info('Header processed and written to output file.')

      CSV.foreach(@input_file, headers: true, col_sep: ',') do |row|
        next unless row['Zipcode/Postal code']

        processed_row = process_row(row.to_hash)
        if processed_row
          update_counts(processed_row, address_count, street_count)
          write_row_to_csv(processed_row, csv, new_headers)
        end
      end
    end

    generate_and_save_logs(address_count, street_count)
    Utils::Logger.info("Processing completed. File saved as: #{@output_file.split('/').last}")
    Utils::Logger.info("Geolocation cache was used #{Utils::CacheManager.location_cache_hits} times and the zip code cache was used #{Utils::CacheManager.zip_code_cache_hits} times")
    Utils::CacheManager.clear!
  end

  private

  def normalize_for_cache(*address_parts)
    address_parts.map { |part| I18n.transliterate(part.to_s.downcase).gsub(/[^a-z0-9]/, '_') }.join('_')
  end

  def fetch_street_name_from_zip_code(zip_code)
    Utils::CacheManager.fetch_zip_code(zip_code) ||
      ZipCodeService.fetch_street_name_from_zip_code(zip_code, @zip_code_cache).tap do |zip_code_info|
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
    zip_code = row['Zipcode/Postal code']&.gsub('-', '')
    return unless zip_code

    Utils::Logger.info("Processing zip code: #{zip_code}")

    zip_code_info = fetch_street_name_from_zip_code(zip_code)

    unless zip_code_info
      Utils::Logger.warn("Zip code not found: #{zip_code}")
      geocode_address(row, row['Destination Address'], zip_code, row['Bairro'], row['City'])
      return row.tap { update_row_complement(row) }
    end

    Utils::Logger.info("Address found: #{zip_code_info[:street_name]}")
    input_street = row['Destination Address'].split(',', 2).first&.strip

    address_normalizer = AddressNormalizerService.new(input_street)
    if address_normalizer.street_name_matches?(zip_code_info[:street_name])
      row['Destination Address'] = "#{zip_code_info[:street_name]},#{row['Destination Address'].split(',', 2).last}"
    else
      Utils::Logger.warn("Trying to correct street name: #{input_street}")
      if (street_info = ZipCodeService.fetch_zip_code_by_street_name(input_street, zip_code_info[:city]))
        row['Destination Address'] = "#{street_info['logradouro']},#{row['Destination Address'].split(',', 2).last}"
      end
    end

    geocode_address(row, row['Destination Address'], zip_code, row['Bairro'], row['City'])
    row.tap { update_row_complement(row) }
  end

  def geocode_address(row, full_address, zip_code, neighborhood, city)
    parts = full_address.split(',')
    street_name = parts.first&.strip
    house_number = parts[1]&.strip&.split&.first
    return unless street_name && house_number

    location = fetch_location(street_name, house_number, zip_code, neighborhood, city)
    return unless location

    row['Latitude'] = location['lat'].to_s
    row['Longitude'] = location['lng'].to_s
  end

  def update_row_complement(row)
    normalizer = AddressNormalizerService.new(row['Destination Address'])
    main, complement = normalizer.separate_complement
    row['Destination Address'] = main
    row['Complement'] = complement ? complement.gsub(/^,\s*/, '') : ''
  end

  def update_counts(row, address_count, street_count)
    sequence = row['Sequence'].to_i
    address = row['Destination Address']
    street = address.split(',').first

    address_count[address][:count] += 1
    address_count[address][:sequences] << sequence

    street_count[street][:count] += 1
    street_count[street][:sequences] << sequence
  end

  def write_row_to_csv(row, csv, headers)
    csv << headers.map do |header|
      %w[Sequence Stop].include?(header) ? row[header].to_s.split('.').first.to_i : row[header]
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
