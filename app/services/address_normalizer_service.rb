# frozen_string_literal: true

class AddressNormalizerService
  PREFIXES = %w[r rua av avenida tv travessa psg passagem pç praça].freeze

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

  def remove_accents(string) = string.downcase.tr('áàâãäéèêëíìîïóòôõöúùûüç()', 'aaaaaeeeiioooouuuuc  ')
  def remove_very_short_words(string) = string.gsub(/\b[a-zA-Z]{1,2}\b,?\s*/, '').strip
  def normalize_address = remove_accents(@address).gsub(/,\s*|\s+/, '_')

  def street_name_matches?(fetched_street)
    input_cleaned = normalize_string(remove_very_short_words(remove_prefixes(@address)))
    input_words = remove_punctuation(remove_accents(input_cleaned)).split

    fetched_cleaned = normalize_string(remove_accents(fetched_street))
    fetched_words = fetched_cleaned.split

    input_words.any? { |word| fetched_words.include?(word) }
  end

  def clean_street_name = remove_prefixes(@address)

  private

  def normalize_string(string) = string.downcase.gsub("'", '')
  def remove_punctuation(string) = string.gsub(/[^a-zA-Z0-9\s]/, '')
  def remove_prefixes(string) = string.split(' ').reject { |word| PREFIXES.include?(word.downcase) }.join(' ').strip
end
