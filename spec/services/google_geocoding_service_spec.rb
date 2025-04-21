# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GoogleGeocodingService do
  let(:api_key) { 'YOUR_TEST_API_KEY' }
  let(:address_normalizer) { instance_double('AddressNormalizerService') }
  let(:service) { GoogleGeocodingService.new(address_normalizer) }
  let(:cache) { {} }
  let(:street_name) { 'Rua dos Testes' }
  let(:house_number) { '123' }
  let(:zip_code) { '01234-567' }
  let(:neighborhood) { 'Testelândia' }
  let(:city) { 'São Paulo' }
  let(:full_address_with_cep) { "#{street_name}, #{house_number}, #{neighborhood}, #{city}, #{zip_code}, Brazil" }
  let(:full_address_without_cep) { "#{street_name}, #{house_number}, #{neighborhood}, #{city}, Brazil" }
  let(:normalized_address_with_cep) { 'rua_dos_testes,_123,_testelandia,_sao_paulo,_01234-567,_brazil' }
  let(:normalized_address_without_cep) { 'rua_dos_testes,_123,_testelandia,_sao_paulo,_brazil' }
  let(:latitude) { -23.5505 }
  let(:longitude) { -46.6333 }
  let(:mock_location) { { 'lat' => latitude, 'lng' => longitude } }

  before do
    allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(api_key)
    allow(address_normalizer).to receive(:normalize_address).and_return(normalized_address_without_cep)
    allow(AddressNormalizerService).to receive(:new).with(street_name).and_return(address_normalizer)
    cache.clear
  end

  describe '#fetch_location_from_google' do
    context 'when the address is in the cache' do
      before do
        cache[normalized_address_without_cep + "_#{house_number}_#{zip_code}_#{neighborhood}_#{city}"] = mock_location
      end

      it 'returns the location from the cache' do
        result = service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)

        expect(result).to eq(mock_location)
      end

      it 'does not make an HTTP request' do
        expect(HTTParty).not_to receive(:get)

        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)
      end

      it 'calls normalize_address on AddressNormalizerService' do
        expect(address_normalizer).to receive(:normalize_address).once

        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)
      end
    end

    context 'when the address is not in the cache' do
      let(:google_response) do
        {
          'results' => [
            {
              'geometry' => {
                'location' => mock_location
              }
            }
          ],
          'status' => 'OK'
        }
      end

      before do
        stub_request(:get, 'https://maps.googleapis.com/maps/api/geocode/json')
          .with(query: hash_including({ address: full_address_without_cep, key: api_key }))
          .to_return(status: 200, body: google_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'makes an HTTP request to the Google Geocoding API with the correct address and API key' do
        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)

        expect(WebMock).to have_requested(:get, "https://maps.googleapis.com/maps/api/geocode/json?address=#{URI::DEFAULT_PARSER.escape(full_address_without_cep)}&key=#{api_key}")
      end

      it 'parses the response and returns the location' do
        result = service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)

        expect(result).to eq(mock_location)
      end

      it 'stores the location in the cache using the correct key' do
        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)

        expect(cache["#{normalized_address_without_cep}_#{house_number}_#{zip_code}_#{neighborhood}_#{city}"]).to eq(mock_location)
      end

      it 'calls normalize_address on AddressNormalizerService' do
        expect(address_normalizer).to receive(:normalize_address).once

        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)
      end
    end

    context 'when the Google Geocoding API returns an error' do
      before do
        stub_request(:get, /maps\.googleapis\.com/)
          .to_return(status: 400, body: { 'error_message' => 'Invalid request' }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns nil' do
        result = service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)

        expect(result).to be_nil
      end

      it 'does not store anything in the cache' do
        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)

        expect(cache).to be_empty
      end

      it 'calls normalize_address on AddressNormalizerService' do
        expect(address_normalizer).to receive(:normalize_address).once

        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)
      end
    end

    context 'when the Google Geocoding API returns no results' do
      let(:empty_response) do
        {
          'results' => [],
          'status' => 'ZERO_RESULTS'
        }
      end

      before do
        stub_request(:get, /maps\.googleapis\.com/)
          .to_return(status: 200, body: empty_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns nil' do
        result = service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)

        expect(result).to be_nil
      end

      it 'does not store anything in the cache' do
        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)

        expect(cache).to be_empty
      end

      it 'calls normalize_address on AddressNormalizerService' do
        expect(address_normalizer).to receive(:normalize_address).once

        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)
      end
    end

    context 'when the HTTP request to Google API fails' do
      before { stub_request(:get, /maps\.googleapis\.com/).to_return(status: 500, body: 'Internal Server Error', headers: {}) }

      it 'returns nil' do
        result = service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)

        expect(result).to be_nil
      end

      it 'does not store anything in the cache' do
        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)

        expect(cache).to be_empty
      end

      it 'calls normalize_address on AddressNormalizerService' do
        expect(address_normalizer).to receive(:normalize_address).once

        service.fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)
      end
    end
  end
end
