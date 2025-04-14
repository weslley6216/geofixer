# frozen_string_literal: true

require_relative 'base_service'

module GoogleDrive
  class UploaderService < BaseService
    def upload(file_path, folder_id)
      Utils::Logger.info("UploaderService: Starting upload for #{File.basename(file_path)} to folder #{folder_id}")

      mime_type = determine_mime_type(file_path)
      metadata = file_metadata(file_path, folder_id, mime_type)

      perform_upload(file_path, metadata, mime_type)
    rescue Google::Apis::Error => e
      Utils::Logger.error("UploaderService: Failed to upload #{File.basename(file_path)} - #{e.message}")
      raise
    end

    private

    def file_metadata(file_path, folder_id, mime_type)
      {
        name: File.basename(file_path),
        parents: [folder_id],
        mime_type: mime_type
      }
    end

    def perform_upload(file_path, metadata, mime_type)
      file = service.create_file(
        metadata,
        fields: 'id',
        upload_source: file_path,
        content_type: mime_type
      )

      Utils::Logger.info("UploaderService: Successfully uploaded #{metadata[:name]} (File ID: #{file.id})")
      file
    end

    def determine_mime_type(file_path)
      case File.extname(file_path).downcase
      when '.csv' then 'text/csv'
      when '.txt' then 'text/plain'
      end
    end
  end
end
