# frozen_string_literal: true

require 'google/apis/drive_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require_relative '../../../app/utils/logger'

module GoogleDrive
  class BaseService
    OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
    APPLICATION_NAME = 'Address Processor'
    DEFAULT_USER_ID = 'default'
    DEFAULT_CREDENTIALS_PATH = './config/credentials.json'
    DEFAULT_TOKEN_PATH = './config/token.yml'
    SCOPE = Google::Apis::DriveV3::AUTH_DRIVE

    def initialize(credentials_path: DEFAULT_CREDENTIALS_PATH, token_path: DEFAULT_TOKEN_PATH)
      @credentials_path = credentials_path
      @token_path = token_path
    end

    def service
      @service ||= Google::Apis::DriveV3::DriveService.new.tap do |drive|
        drive.client_options.application_name = APPLICATION_NAME
        drive.authorization = authorize
      end
    end

    def ensure_directory_exists(directory_path)
      FileUtils.mkdir_p(directory_path) unless File.directory?(directory_path)
    end

    private

    def authorize
      client_id = Google::Auth::ClientId.from_file(@credentials_path)
      token_store = Google::Auth::Stores::FileTokenStore.new(file: @token_path)
      authorizer = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)

      authorizer.get_credentials(DEFAULT_USER_ID) || request_authorization(authorizer)
    end

    def request_authorization(authorizer)
      display_auth_prompt(authorizer)
      code = obtain_authorization_code
      process_authorization(authorizer, code)
    rescue StandardError => e
      handle_authorization_error(e)
    end

    def display_auth_prompt(authorizer)
      url = authorizer.get_authorization_url(base_url: OOB_URI)
      Utils::Logger.info('Google Drive Auth: Please open the following URL in your browser:')
      Utils::Logger.info(url)
      Utils::Logger.info('Google Drive Auth: Enter the authorization code:')
    end

    def obtain_authorization_code = gets.chomp

    def process_authorization(authorizer, code)
      Utils::Logger.debug('Authorization code received, requesting token...')
      authorizer.get_and_store_credentials_from_code(
        user_id: DEFAULT_USER_ID,
        code: code,
        base_url: OOB_URI
      )
      Utils::Logger.info('Authorization completed successfully')
    end

    def handle_authorization_error(error)
      Utils::Logger.error("Authorization failed: #{error.message}")
      raise
    end
  end
end
