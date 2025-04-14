# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GoogleDrive::DownloaderService do
  let(:credentials_path) { 'spec/fixtures/credentials.json' }
  let(:token_path) { 'tmp/test_token.yml' }
  let(:service) { described_class.new(credentials_path:, token_path:) }
  let(:mock_logger) { instance_double(Logger) }

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

  describe '#download' do
    let(:file_id) { 'test_file_123' }
    let(:destination) { 'tmp/test_download.txt' }

    before do
      FileUtils.mkdir_p('tmp')
      FileUtils.rm_f(destination)
    end

    context 'when successful' do
      before do
        stub_request(:get, "https://www.googleapis.com/drive/v3/files/#{file_id}?alt=media")
          .to_return(status: 200, body: 'file content')
      end

      it 'downloads the file successfully' do
        expect(mock_logger).to receive(:info).with("DownloaderService: Starting download for file ID: #{file_id}")
        expect(mock_logger).to receive(:info).with("DownloaderService: Successfully downloaded file to: #{destination}")

        expect(service.download(file_id, destination)).to eq(destination)
        expect(File.read(destination)).to eq('file content')
      end
    end

    context 'when API fails' do
      before do
        allow(service).to receive(:service).and_return(double('drive_service'))
        allow(service.service).to receive(:get_file).and_raise(Google::Apis::ClientError.new('Invalid request'))
      end

      it 'logs the error and raises exception' do
        expect(mock_logger).to receive(:error).with("DownloaderService: Failed to download file #{file_id} - Invalid request")
        expect { service.download(file_id, destination) }.to raise_error(Google::Apis::ClientError)
      end

      it 'does not create the file' do
        expect { service.download(file_id, destination) }.to raise_error(Google::Apis::ClientError)
        expect(File.exist?(destination)).to be false
      end
    end
  end

  describe '#files_in_folder' do
    let(:folder_id) { 'test_folder_456' }

    before { allow(service).to receive(:service).and_return(double('drive_service')) }

    it 'returns files from the folder' do
      mock_response = double('response', files: %w[file1 file2])
      expect(service.service).to receive(:list_files)
        .with(q: "'#{folder_id}' in parents", fields: 'files(id, name, modifiedTime)')
        .and_return(mock_response)

      expect(mock_logger).to receive(:info).with("DownloaderService: Listing files in folder ID: #{folder_id}")
      expect(service.files_in_folder(folder_id)).to eq(%w[file1 file2])
    end
  end
end
