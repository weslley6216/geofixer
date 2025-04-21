# frozen_string_literal: true

require 'dotenv/load'
require 'httparty'
require 'uri'

class GoogleGeocodingService
  def initialize(address_normalizer, api_key = ENV['GOOGLE_API_KEY'])
    @api_key = api_key
    @address_normalizer = address_normalizer
  end

  def fetch_location_from_google(street_name, house_number, zip_code, neighborhood, city, cache)
    address = "#{street_name}, #{house_number}, #{neighborhood}, #{city}, Brazil"
    normalized_address = @address_normalizer.normalize_address
    cache_key = "#{normalized_address}_#{house_number}_#{zip_code}_#{neighborhood}_#{city}"

    cache.fetch(cache_key) { fetch_geocode(address)&.tap { |result| cache[cache_key] = result } }
  end

  def fetch_geocode(address)
    url = "https://maps.googleapis.com/maps/api/geocode/json?address=#{URI::DEFAULT_PARSER.escape(address)}&key=#{@api_key}"
    response = HTTParty.get(url)
    return unless response.code == 200

    data = response.parsed_response
    return unless data['results']&.any?

    data['results'].first['geometry']['location']
  end
end
