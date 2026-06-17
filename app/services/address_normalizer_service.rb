# frozen_string_literal: true
require_relative '../utils/i18n'

class AddressNormalizerService
  PREFIXES = %w[r rua av avenida tv travessa psg passagem pç praça].freeze
  # Connector words that carry no distinguishing meaning when comparing street
  # names. Shorter connectors (de/da/do/e) are already dropped as short words.
  CONNECTORS = %w[das dos].freeze

  def initialize(address)
    @address = address
  end

  def separate_complement
    pattern = /\A(?<street>.*?),\s*(?<number>\d+)(?:,\s*(?<complement>.*))?\z/
    match = @address.match(pattern)

    return [@address, nil] unless match

    main_address = "#{match[:street]}, #{match[:number]}".strip
    [main_address, match[:complement]&.strip]
  end

  def remove_accents(string) = I18n.transliterate(string.downcase)
  def remove_very_short_words(string) = string.gsub(/\b[a-zA-Z]{1,2}\b,?\s*/, '').strip

  def street_name_matches?(fetched_street)
    input_words = significant_words(@address)
    fetched_words = significant_words(fetched_street)
    return false if input_words.empty? || fetched_words.empty?

    input_words.any? { |word| fetched_words.include?(word) }
  end

  def clean_street_name = remove_prefixes(@address)

  private

  # Distinguishing words of a street name: prefixes, short words, connectors,
  # accents and punctuation removed.
  def significant_words(string)
    stripped = remove_very_short_words(remove_prefixes(string))
    remove_punctuation(remove_accents(stripped)).split.reject { |word| CONNECTORS.include?(word) }
  end

  def remove_punctuation(string) = string.gsub(/[^a-zA-Z0-9\s]/, '')
  def remove_prefixes(string) = string.split(' ').reject { |word| PREFIXES.include?(word.downcase) }.join(' ').strip
end
