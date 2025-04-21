# frozen_string_literal: true

require 'spec_helper'
require 'byebug'

RSpec.describe Utils::CacheManager do
  let(:zip_code) { '12345678' }
  let(:zip_code_data) { { street_name: 'Rua das Flores', city: 'São Paulo' } }
  let(:cache_key) { 'rua_flores_100_12345678_bairro_sp' }
  let(:location_data) { { 'lat' => -23.5, 'lng' => -46.6 } }

  describe '.instance' do
    it 'returns the same instance every time' do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be(instance2)
    end
  end

  describe '.store_zip_code and .fetch_zip_code' do
    it 'returns nil if the zip code is not cached' do
      expect(described_class.fetch_zip_code(zip_code)).to be_nil
      expect(described_class.zip_code_cache_hits).to eq(0)
    end

    it 'stores and retrieves data from the zip code cache' do
      described_class.store_zip_code(zip_code, zip_code_data)

      expect(described_class.fetch_zip_code(zip_code)).to eq(zip_code_data)
      expect(described_class.zip_code_cache_hits).to eq(1)
    end

    it 'stores different data for different zip codes' do
      other_zip_code = '87654321'
      other_zip_code_data = { street_name: 'Rua das Acácias', city: 'Diadema' }

      described_class.store_zip_code(zip_code, zip_code_data)
      described_class.store_zip_code(other_zip_code, other_zip_code_data)

      expect(described_class.fetch_zip_code(zip_code)).to eq(zip_code_data)
      expect(described_class.fetch_zip_code(other_zip_code)).to eq(other_zip_code_data)
    end
  end

  describe '.store_location and .fetch_location' do
    it 'returns nil if the location is not cached' do
      expect(described_class.fetch_location(cache_key)).to be_nil
      expect(described_class.location_cache_hits).to eq(0)
    end

    it 'stores and retrieves data from the location cache' do
      described_class.store_location(cache_key, location_data)

      expect(described_class.fetch_location(cache_key)).to eq(location_data)
      expect(described_class.location_cache_hits).to eq(1)
    end
  end

  describe '.clear!' do
    it 'clears the caches and resets the hit counters' do
      described_class.store_zip_code(zip_code, zip_code_data)
      described_class.store_location(cache_key, location_data)

      described_class.clear!

      expect(described_class.fetch_zip_code(zip_code)).to be_nil
      expect(described_class.fetch_location(cache_key)).to be_nil
      expect(described_class.zip_code_cache_hits).to eq(0)
      expect(described_class.location_cache_hits).to eq(0)
    end
  end
end
