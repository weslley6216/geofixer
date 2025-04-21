# frozen_string_literal: true

require 'logger'

module Utils
  class Logger
    class << self
      attr_accessor :instance

      def setup
        self.instance ||= ::Logger.new($stdout).tap do |log|
          log.level = ::Logger::INFO
          log.formatter = proc { |severity, datetime, _, msg|
            "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} - #{msg}\n"
          }
        end
      end

      def info(message, source: nil)
        message = format_message(message, source)
        instance.info(message)
      end

      def error(message, source: nil)
        message = format_message(message, source)
        instance.error(message)
      end

      def warn(message, source: nil)
        message = format_message(message, source)
        instance.warn(message)
      end

      def debug(message, source: nil)
        message = format_message(message, source)
        instance.debug(message)
      end

      private

      def format_message(message, source) = source ? "[#{source}] #{message}" : message
    end
  end
end

Utils::Logger.setup
