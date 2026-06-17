# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'logger'

module Utils
  # Thin wrapper around Net::HTTP that adds connection timeouts, retries on
  # transient network failures and JSON parsing. Returns the parsed body on a
  # 2xx response, or nil on any failure (so callers never hang or raise).
  module HttpClient
    DEFAULT_TIMEOUT = 5
    DEFAULT_RETRIES = 2
    RETRYABLE_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, Timeout::Error,
      Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError
    ].freeze

    module_function

    def get_json(url, timeout: DEFAULT_TIMEOUT, retries: DEFAULT_RETRIES)
      uri = URI(url)
      attempts = 0

      begin
        attempts += 1
        response = perform_get(uri, timeout)
        return unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue *RETRYABLE_ERRORS => e
        retry if attempts <= retries

        Utils::Logger.warn("HTTP request to #{uri.host} failed after #{attempts} attempts: #{e.message}")
        nil
      rescue JSON::ParserError => e
        Utils::Logger.warn("Failed to parse JSON from #{uri.host}: #{e.message}")
        nil
      end
    end

    def perform_get(uri, timeout)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.get(uri.request_uri)
    end
  end
end
