# frozen_string_literal: true

module Utils
  class CacheManager
    attr_reader :zip_code_hits, :location_hits

    def initialize
      @zip_code_cache = {}
      @location_cache = {}
      @zip_code_hits = 0
      @location_hits = 0
    end

    class << self
      def instance = @instance ||= new
      def zip_code_cache_hits = instance.zip_code_hits
      def location_cache_hits = instance.location_hits
      def fetch_zip_code(zip_code) = instance.fetch_zip_code_instance(zip_code)
      def store_zip_code(zip_code, data) = instance.store_zip_code_instance(zip_code, data)
      def fetch_location(cache_key) = instance.fetch_location_instance(cache_key)
      def store_location(cache_key, location) = instance.store_location_instance(cache_key, location)
      def clear! = instance.clear_instance
    end

    def fetch_zip_code_instance(zip_code)
      return unless @zip_code_cache&.key?(zip_code)

      @zip_code_hits += 1
      @zip_code_cache[zip_code]
    end

    def store_zip_code_instance(zip_code, data)
      @zip_code_cache[zip_code] = data
    end

    def fetch_location_instance(cache_key)
      return unless @location_cache&.key?(cache_key)

      @location_hits += 1
      @location_cache[cache_key]
    end

    def store_location_instance(cache_key, location)
      @location_cache[cache_key] = location
    end

    def clear_instance
      @zip_code_cache.clear
      @location_cache.clear
      @zip_code_hits = 0
      @location_hits = 0
    end
  end
end
