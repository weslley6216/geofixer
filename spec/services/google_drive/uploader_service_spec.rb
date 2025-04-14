# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GoogleDrive::UploaderService do
  let(:credentials_path) { 'spec/fixtures/credentials.json' }
  let(:token_path) { 'tmp/test_token.yml' }
  let(:service) { described_class.new(credentials_path:, token_path:) }
  let(:mock_logger) { instance_double(Logger) }
  let(:file_path) { 'spec/fixtures/test_file.txt' }
  let(:folder_id) { 'test_folder_456' }

  before do
    allow(mock_logger).to receive(:info)
    allow(mock_logger).to receive(:error)
    Utils::Logger.instance = mock_logger

    auth_client = double('Google::Auth::UserAuthorizer')
    credentials = double('credentials', access_token: 'test_token')

    allow(Google::Auth::ClientId).to receive(:from_file).with(credentials_path).and_return(double('client_id'))
    allow(Google::Auth::Stores::FileTokenStore).to receive(:new).with(file: token_path).and_return(double('token_store'))
    allow(Google::Auth::UserAuthorizer).to receive(:new).and_return(auth_client)
    allow(auth_client).to receive(:get_credentials).and_return(credentials)
  end

  describe '#upload' do
    before do
      allow(service).to receive(:service).and_return(double('drive_service'))
      allow(File).to receive(:basename).with(file_path).and_return('test_file.txt')
    end

    context 'when successful' do
      let(:mock_response) { double('response', id: 'uploaded_file_id') }

      before do
        allow(service.service).to receive(:create_file).and_return(mock_response)
      end

      it 'uploads the file successfully' do
        expect(mock_logger).to receive(:info)
          .with("UploaderService: Starting upload for test_file.txt to folder #{folder_id}")
        expect(mock_logger).to receive(:info)
          .with("UploaderService: Successfully uploaded test_file.txt (File ID: #{mock_response.id})")

        expect(service.upload(file_path, folder_id)).to eq(mock_response)
      end

      it 'calls the API with correct parameters' do
        expect(service.service).to receive(:create_file)
          .with(
            { name: 'test_file.txt', parents: [folder_id], mime_type: 'text/plain' },
            hash_including(
              upload_source: file_path,
              content_type: 'text/plain',
              fields: 'id'
            )
          ).and_return(mock_response)

        service.upload(file_path, folder_id)
      end
    end

    context 'when API fails' do
      before do
        allow(service.service).to receive(:create_file).and_raise(Google::Apis::Error.new('Upload error'))
      end

      it 'logs the error and raises exception' do
        expect(mock_logger).to receive(:error)
          .with('UploaderService: Failed to upload test_file.txt - Upload error')
        expect { service.upload(file_path, folder_id) }.to raise_error(Google::Apis::Error)
      end
    end
  end
end
