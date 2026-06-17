# frozen_string_literal: true

require 'uri'
require_relative '../utils/http_client'

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
    data = Utils::HttpClient.get_json(url)
    return unless data && data['results']&.any?

    data['results'].first['geometry']['location']
  end
end
