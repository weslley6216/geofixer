# frozen_string_literal: true

require 'httparty'
require 'uri'

class GoogleGeocodingService
  def initialize(api_key = ENV['GOOGLE_API_KEY'])
    @api_key = api_key
  end

  def fetch_location_from_google(street_name, house_number, neighborhood, city)
    address = "#{street_name}, #{house_number}, #{neighborhood}, #{city}, Brazil"
    fetch_geocode(address)
  end

  private

  def fetch_geocode(address)
    url = "https://maps.googleapis.com/maps/api/geocode/json?address=#{URI::DEFAULT_PARSER.escape(address)}&key=#{@api_key}"
    response = HTTParty.get(url)
    return unless response.code == 200

    data = response.parsed_response
    return unless data['results']&.any?

    data['results'].first['geometry']['location']
  end
end
