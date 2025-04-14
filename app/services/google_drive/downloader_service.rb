# frozen_string_literal: true

require_relative 'base_service'

module GoogleDrive
  class DownloaderService < BaseService
    def download(file_id, destination_path)
      ensure_directory_exists(File.dirname(destination_path))

      Utils::Logger.info("DownloaderService: Starting download for file ID: #{file_id}")
      service.get_file(file_id, download_dest: destination_path)
      Utils::Logger.info("DownloaderService: Successfully downloaded file to: #{destination_path}")

      destination_path
    rescue Google::Apis::Error => e
      Utils::Logger.error("DownloaderService: Failed to download file #{file_id} - #{e.message}")
      raise
    end

    def files_in_folder(folder_id, mime_type: nil)
      query = "'#{folder_id}' in parents"
      query += " and mimeType='#{mime_type}'" if mime_type

      Utils::Logger.info("DownloaderService: Listing files in folder ID: #{folder_id}")
      response = service.list_files(q: query, fields: 'files(id, name, modifiedTime)')

      response.files
    rescue Google::Apis::Error => e
      Utils::Logger.error("DownloaderService: Failed to list files in folder #{folder_id} - #{e.message}")
      raise
    end
  end
end
