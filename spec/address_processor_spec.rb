# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AddressProcessor do
  let(:input_file) { 'spec/fixtures/input.csv' }
  let(:output_file) { 'spec/tmp/output.csv' }
  let(:log_file) { 'spec/tmp/log.txt' }
  let(:processor) { described_class.new(input_file, output_file, log_file) }

  before do
    CSV.open(input_file, 'w', col_sep: ',') do |csv|
      csv << ['Sequence', 'Stop', 'Destination Address', 'Zipcode/Postal code', 'Bairro', 'City', 'Latitude', 'Longitude']
      csv << ['1', '1', 'Rua Fictícia, 123', '12345678', 'Centro', 'São Paulo', '-123', '-456']
    end

    allow(Utils::Logger).to receive(:info)
    allow(Utils::Logger).to receive(:warn)

    allow(ZipCodeService).to receive(:fetch_street_name_from_zip_code).and_return({ street_name: 'Rua Fictícia', city: 'São Paulo' })
    allow(ZipCodeService).to receive(:fetch_zip_code_by_street_name).and_return(nil)

    normalizer_instance = instance_double(AddressNormalizerService, normalize_address: 'Rua Ficticia', street_name_matches?: true,
                                                                    separate_complement: ['Rua Fictícia, 123', nil])
    allow(AddressNormalizerService).to receive(:new).and_return(normalizer_instance)

    allow(GoogleGeocodingService).to receive(:new).and_return(
      instance_double(GoogleGeocodingService, fetch_location_from_google: { 'lat' => -23.55052, 'lng' => -46.633308 })
    )

    allow(LogGeneratorService).to receive(:generate_top_items_log).and_return("Top endereços\nTop ruas\nTop travessas")
    allow(LogGeneratorService).to receive(:save_logs_to_file)

    allow(Utils::CacheManager).to receive(:fetch_zip_code).and_return(nil)
    allow(Utils::CacheManager).to receive(:store_zip_code)
    allow(Utils::CacheManager).to receive(:fetch_location).and_return(nil)
    allow(Utils::CacheManager).to receive(:store_location)
    allow(Utils::CacheManager).to receive(:zip_code_cache_hits).and_return(1)
    allow(Utils::CacheManager).to receive(:location_cache_hits).and_return(1)
    allow(Utils::CacheManager).to receive(:clear!)
  end

  after do
    FileUtils.rm_f(input_file)
    FileUtils.rm_f(output_file)
    FileUtils.rm_f(log_file)
  end

  describe '#process_file' do
    it 'creates a new CSV file with header and one processed row' do
      processor.process_file

      output_lines = CSV.read(output_file, headers: true, col_sep: ',')

      expect(output_lines.length).to eq(1)
      expect(output_lines.headers).to include('Complement')
      expect(output_lines.first['Destination Address']).to eq('Rua Fictícia, 123')
      expect(output_lines.first['Latitude']).to eq('-23.55052')
      expect(output_lines.first['Longitude']).to eq('-46.633308')
    end

    it 'uses CacheManager to fetch and store data' do
      expect(Utils::CacheManager).to receive(:fetch_zip_code).with('12345678').and_return(nil)
      expect(Utils::CacheManager).to receive(:store_zip_code).with('12345678', { street_name: 'Rua Fictícia', city: 'São Paulo' })
      expect(Utils::CacheManager).to receive(:fetch_location).with(kind_of(String)).and_return(nil)
      expect(Utils::CacheManager).to receive(:store_location).with(kind_of(String), { 'lat' => -23.55052, 'lng' => -46.633308 })

      processor.process_file
    end

    it 'generates address and street logs' do
      expect(LogGeneratorService).to receive(:generate_top_items_log).at_least(:once)
      expect(LogGeneratorService).to receive(:save_logs_to_file).with(log_file, kind_of(String), kind_of(String), kind_of(String))

      processor.process_file
    end

    it 'clear cache after processing' do
      expect(Utils::CacheManager).to receive(:clear!)

      processor.process_file
    end

    it 'logs cache hits in the log' do
      expect(Utils::Logger).to receive(:info).with(/Geolocation cache was used 1 times and the zip code cache was used 1 times/)

      processor.process_file
    end
  end
end
