# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LogGeneratorService do
  let(:log_file) { 'test_log.txt' }
  let(:address_count) do
    {
      'Rua A, 123' => { count: 5, sequences: [1, 2, 3, 4, 5] },
      'Rua B, 456' => { count: 4, sequences: [6, 7, 8, 9] },
      'Rua C, 789' => { count: 4, sequences: [10, 11, 12, 13] },
      'Rua D, 10' => { count: 3, sequences: [14, 15, 16] },
      'Rua E, 20' => { count: 2, sequences: [17, 18] },
      'Rua F, 30' => { count: 2, sequences: [19, 20] },
      'Rua G, 40' => { count: 1, sequences: [21] }
    }
  end
  let(:street_count) do
    {
      'Rua A' => { count: 5, sequences: [1, 2, 3, 4, 5] },
      'Rua B' => { count: 4, sequences: [6, 7, 8, 9] },
      'Rua C' => { count: 4, sequences: [10, 11, 12, 13] },
      'Travessa X' => { count: 2, sequences: [22, 23] },
      'Passagem Y' => { count: 1, sequences: [24] }
    }
  end
  let(:alley_logs) { ['2 pacotes na Travessa X, com as ordens 22, 23', '1 pacote na Passagem Y, com a ordem 24'] }
  let(:address_logs) do
    [
      '5 pacotes na Rua A, 123, com as ordens 1, 2, 3, 4, 5',
      '4 pacotes na Rua B, 456, com as ordens 6, 7, 8, 9',
      '4 pacotes na Rua C, 789, com as ordens 10, 11, 12, 13',
      '3 pacotes na Rua D, 10, com as ordens 14, 15, 16',
      '2 pacotes na Rua E, 20, com as ordens 17, 18',
      '2 pacotes na Rua F, 30, com as ordens 19, 20',
      '1 pacote na Rua G, 40, com a ordem 21'
    ]
  end
  let(:street_logs) do
    [
      '5 pacotes na Rua A, com as ordens 1, 2, 3, 4, 5',
      '4 pacotes na Rua B, com as ordens 6, 7, 8, 9',
      '4 pacotes na Rua C, com as ordens 10, 11, 12, 13',
      '2 pacotes na Travessa X, com as ordens 22, 23',
      '1 pacote na Passagem Y, com a ordem 24'
    ]
  end

  before do
    allow(Utils::Logger).to receive(:info)
    File.delete(log_file) if File.exist?(log_file)
  end

  describe '.save_logs_to_file' do
    it 'creates a log file with the correct content' do
      LogGeneratorService.save_logs_to_file(log_file, address_logs.take(10), street_logs.take(10),
                                            alley_logs.take(10))

      expect(File.exist?(log_file)).to be true
      content = File.read(log_file)

      expect(content).to include('Endereços com mais pedidos:')
      address_logs.take(10).each do |line|
        expect(content).to include(line)
        expect(content).to include('---------------------------------')
      end

      expect(content).to include("\nRuas com mais pedidos:")
      street_logs.take(10).each do |line|
        expect(content).to include(line)
        expect(content).to include('---------------------------------')
      end

      expect(content).to include("\nTravessas e/ou Passagens com mais pedidos:")
      alley_logs.take(10).each do |line|
        expect(content).to include(line)
        expect(content).to include('---------------------------------')
      end

      expect(Utils::Logger).to have_received(:info).with("Logs saved to file: #{log_file}")
    end
  end

  describe '.generate_top_items_log' do
    it 'returns a formatted log array for the top N items' do
      top_addresses = LogGeneratorService.generate_top_items_log(address_count, 'Endereços', 7)
      expect(top_addresses).to eq([
                                    '5 pacotes na Rua A, 123, com as ordens 1, 2, 3, 4, 5',
                                    '4 pacotes na Rua B, 456, com as ordens 6, 7, 8, 9',
                                    '4 pacotes na Rua C, 789, com as ordens 10, 11, 12, 13',
                                    '3 pacotes na Rua D, 10, com as ordens 14, 15, 16',
                                    '2 pacotes na Rua E, 20, com as ordens 17, 18',
                                    '2 pacotes na Rua F, 30, com as ordens 19, 20',
                                    '1 pacote na Rua G, 40, com a ordem 21'
                                  ])

      top_streets = LogGeneratorService.generate_top_items_log(street_count, 'Ruas', 5)
      expect(top_streets).to eq([
                                  '5 pacotes na Rua A, com as ordens 1, 2, 3, 4, 5',
                                  '4 pacotes na Rua B, com as ordens 6, 7, 8, 9',
                                  '4 pacotes na Rua C, com as ordens 10, 11, 12, 13',
                                  '2 pacotes na Travessa X, com as ordens 22, 23',
                                  '1 pacote na Passagem Y, com a ordem 24'
                                ])

      top_alleys = street_count.select { |name, _| name.match?(/Travessa|Passagem/) }
                               .then { |filtered| LogGeneratorService.generate_top_items_log(filtered, 'Travessas e/ou Passagens', 10) }
      expect(top_alleys).to eq([
                                 '2 pacotes na Travessa X, com as ordens 22, 23',
                                 '1 pacote na Passagem Y, com a ordem 24'
                               ])
    end

    it 'handles singular and plural forms correctly' do
      single_address = { 'Rua D, 1' => { count: 1, sequences: [20] } }
      multiple_address = { 'Rua E, 5' => { count: 2, sequences: [25, 26] } }

      log = LogGeneratorService.generate_top_items_log(single_address, 'Endereços', 1)
      log_multiple = LogGeneratorService.generate_top_items_log(multiple_address, 'Endereços', 1)

      expect(log).to eq(['1 pacote na Rua D, 1, com a ordem 20'])
      expect(log_multiple).to eq(['2 pacotes na Rua E, 5, com as ordens 25, 26'])
    end
  end

  describe '.pluralize' do
    it 'returns the singular form when count is 1' do
      expect(LogGeneratorService.pluralize(1, 'item', 'itens')).to eq('item')
    end

    it 'returns the plural form when count is greater than 1' do
      expect(LogGeneratorService.pluralize(2, 'item', 'itens')).to eq('itens')
    end
  end
end
