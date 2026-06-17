# frozen_string_literal: true

module Utils
  # Process-wide in-memory cache for zip code lookups and geocoded locations,
  # with hit counters for reporting. State lives on the class itself; call
  # `clear!` between runs to reset.
  class CacheManager
    @zip_code_cache = {}
    @location_cache = {}
    @zip_code_cache_hits = 0
    @location_cache_hits = 0

    class << self
      attr_reader :zip_code_cache_hits, :location_cache_hits

      def fetch_zip_code(zip_code)
        read(@zip_code_cache, zip_code) { @zip_code_cache_hits += 1 }
      end

      def store_zip_code(zip_code, data)
        @zip_code_cache[zip_code] = data
      end

      def fetch_location(cache_key)
        read(@location_cache, cache_key) { @location_cache_hits += 1 }
      end

      def store_location(cache_key, location)
        @location_cache[cache_key] = location
      end

      def clear!
        @zip_code_cache = {}
        @location_cache = {}
        @zip_code_cache_hits = 0
        @location_cache_hits = 0
      end

      private

      def read(store, key)
        return unless store.key?(key)

        yield
        store[key]
      end
    end
  end
end
