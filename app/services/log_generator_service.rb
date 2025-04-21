# frozen_string_literal: true

class LogGeneratorService
  class << self
    def save_logs_to_file(log_file, address_log_lines, street_log_lines, alley_log_lines)
      File.open(log_file, 'w:UTF-8') do |file|
        file.puts 'Endereços com mais pedidos:'
        file.puts ''
        address_log_lines.each do |log_line|
          file.puts log_line
          file.puts '---------------------------------'
        end

        file.puts "\nRuas com mais pedidos:"
        file.puts ''
        street_log_lines.each do |log_line|
          file.puts log_line
          file.puts '---------------------------------'
        end

        file.puts "\nTravessas e/ou Passagens com mais pedidos:"
        file.puts ''
        alley_log_lines.each do |log_line|
          file.puts log_line
          file.puts '---------------------------------'
        end
      end
      Utils::Logger.info("Logs saved to file: #{log_file}")
    end

    def generate_top_items_log(items_count_data, _item_type, top_n)
      items_count_data.sort_by { |_item, data| -data[:count] }
                      .first(top_n)
                      .map do |item_name, data|
                        "#{data[:count]} #{pluralize(data[:count], 'pacote', 'pacotes')} na #{item_name}, " \
                        "com #{pluralize(data[:sequences].size, 'a ordem', 'as ordens')} " \
                        "#{data[:sequences].map(&:to_s).join(', ')}"
                      end
    end

    def pluralize(count, singular, plural) = count == 1 ? singular : plural
  end
end
