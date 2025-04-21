# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AddressNormalizerService do
  describe '#separate_complement' do
    it 'separates the main address and complement correctly' do
      service = AddressNormalizerService.new('Avenida Dom Jaime de Barros Câmara, 885, 131 bloco A')

      main_address, complement = service.separate_complement

      expect(main_address).to eq('Avenida Dom Jaime de Barros Câmara, 885')
      expect(complement).to eq('131 bloco A')
    end

    it 'returns nil for complement when there is no complement' do
      service = AddressNormalizerService.new('Rua B, 789')

      main_address, complement = service.separate_complement

      expect(main_address).to eq('Rua B, 789')
      expect(complement).to be_nil
    end
  end

  describe '#remove_accents' do
    it 'removes accents from the address' do
      service = AddressNormalizerService.new('Rua Água Funda, 10')

      result = service.remove_accents(service.instance_variable_get(:@address))

      expect(result).to eq('rua agua funda, 10')
    end
  end

  describe '#remove_very_short_words' do
    it 'removes short words from the address' do
      service = AddressNormalizerService.new('Rua da Paz, 10')

      result = service.remove_very_short_words(service.instance_variable_get(:@address))

      expect(result).to eq('Rua Paz, 10')
    end
  end

  describe '#normalize_address' do
    it 'normalizes the address' do
      service = AddressNormalizerService.new('Rua Água Funda, 10')

      result = service.normalize_address

      expect(result).to eq('rua_agua_funda_10')
    end
  end

  describe '#street_name_matches?' do
    it 'returns true if the street names match' do
      service = AddressNormalizerService.new('Rua da Paz, 10')

      result = service.street_name_matches?('Rua da Paz')

      expect(result).to be true
    end

    it 'returns true if the street names match even with accents' do
      service = AddressNormalizerService.new('Rua Água Funda, 10')

      result = service.street_name_matches?('Rua Agua Funda')

      expect(result).to be true
    end

    it 'returns false if the street names do not match' do
      service = AddressNormalizerService.new('Rua da Paz, 10')

      result = service.street_name_matches?('Rua da Alegria')

      expect(result).to be false
    end
  end

  describe '#clean_street_name' do
    it 'removes prefixes from the street name' do
      service = AddressNormalizerService.new('Rua da Paz, 10')

      result = service.clean_street_name

      expect(result).to eq('da Paz, 10')
    end
  end
end
