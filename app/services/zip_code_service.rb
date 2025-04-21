# frozen_string_literal: true

require 'httparty'
require 'uri'

class ZipCodeService
  class << self
    def fetch_street_name_from_zip_code(zip_code, cache)
      cache.fetch(zip_code) do
        response = HTTParty.get(viacep_url(zip_code))
        next unless response.success?

        data = response.parsed_response
        next if data['erro']

        cache_zip_data(cache, zip_code, data)
      end
    end

    def fetch_zip_code_by_street_name(street_name, city)
      url = street_search_url(street_name, city)
      Utils::Logger.info("Fetching URL: #{url}")

      response = HTTParty.get(url)
      response.success? ? response.parsed_response : nil
    end

    private

    def viacep_url(zip_code)
      "https://viacep.com.br/ws/#{zip_code}/json/"
    end

    def street_search_url(street_name, city)
      normalized = AddressNormalizerService.new(street_name)
      clean_name = normalized.remove_accents(normalized.clean_street_name)
                             .gsub(' ', '%20')
                             .downcase

      "https://viacep.com.br/ws/SP/#{URI.encode_www_form_component(city)}/#{clean_name}/json/"
    end

    def cache_zip_data(cache, zip_code, data)
      result = {
        street_name: data['logradouro'],
        city: data['localidade']
      }
      cache[zip_code] = result
      result
    end
  end
end
