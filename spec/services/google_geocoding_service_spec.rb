# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GoogleGeocodingService do
  let(:api_key) { 'YOUR_TEST_API_KEY' }
  let(:service) { GoogleGeocodingService.new }
  let(:street_name) { 'Rua dos Testes' }
  let(:house_number) { '123' }
  let(:neighborhood) { 'Testelândia' }
  let(:city) { 'São Paulo' }
  let(:full_address) { "#{street_name}, #{house_number}, #{neighborhood}, #{city}, Brazil" }
  let(:latitude) { -23.5505 }
  let(:longitude) { -46.6333 }
  let(:mock_location) { { 'lat' => latitude, 'lng' => longitude } }

  before do
    allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(api_key)
  end

  describe '#fetch_location_from_google' do
    context 'when the API responds successfully with results' do
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
        stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json.*})
          .with { |req| req.uri.query.include?(URI::DEFAULT_PARSER.escape(full_address)) }
          .to_return(status: 200, body: google_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'calls the Google API with the correct address' do
        service.fetch_location_from_google(street_name, house_number, neighborhood, city)

        expect(WebMock).to have_requested(:get, /maps\.googleapis\.com/)
          .with { |req| req.uri.query.include?(URI::DEFAULT_PARSER.escape(full_address)) }
      end

      it 'returns the location from the API' do
        result = service.fetch_location_from_google(street_name, house_number, neighborhood, city)

        expect(result).to eq(mock_location)
      end
    end

    context 'when the API returns an error status' do
      before do
        stub_request(:get, /maps\.googleapis\.com/)
          .to_return(status: 400, body: { error_message: 'Invalid request' }.to_json)
      end

      it 'returns nil' do
        result = service.fetch_location_from_google(street_name, house_number, neighborhood, city)

        expect(result).to be_nil
      end
    end

    context 'when the API responds with no results' do
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
        result = service.fetch_location_from_google(street_name, house_number, neighborhood, city)

        expect(result).to be_nil
      end
    end

    context 'when the API request fails' do
      before do
        stub_request(:get, /maps\.googleapis\.com/)
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'returns nil' do
        result = service.fetch_location_from_google(street_name, house_number, neighborhood, city)

        expect(result).to be_nil
      end
    end
  end
end
