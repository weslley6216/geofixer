# frozen_string_literal: true

require 'uri'
require_relative '../utils/http_client'

class ZipCodeService
  class << self
    def fetch_street_name_from_zip_code(zip_code)
      data = Utils::HttpClient.get_json(viacep_url(zip_code))
      return if data.nil? || data['erro']

      { street_name: data['logradouro'], city: data['localidade'], uf: data['uf'] }
    end

    def fetch_zip_code_by_street_name(street_name, city, uf)
      url = street_search_url(street_name, city, uf)
      Utils::Logger.info("Fetching URL: #{url}")

      Utils::HttpClient.get_json(url)
    end

    private

    def viacep_url(zip_code)
      "https://viacep.com.br/ws/#{zip_code}/json/"
    end

    def street_search_url(street_name, city, uf)
      normalized = AddressNormalizerService.new(street_name)
      clean_name = normalized.remove_accents(normalized.clean_street_name)
                             .gsub(' ', '%20')
                             .downcase

      "https://viacep.com.br/ws/#{uf}/#{URI.encode_www_form_component(city)}/#{clean_name}/json/"
    end
  end
end
