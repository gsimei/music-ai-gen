# frozen_string_literal: true

class UploadSoundtrackInputToMurekaJob < ApplicationJob
  queue_as :ai

  def perform(order_id, input_id = nil)
    order = Order.find(order_id)
    soundtrack_input = nil
    order.with_lock do
      return unless order.paid? && order.soundtrack_enabled?
      soundtrack_input = order.soundtrack_input
      return unless soundtrack_input && (input_id.nil? || soundtrack_input.id == input_id)
      return unless soundtrack_input.mureka_file_status == "pending"
      unless soundtrack_input.processable_file?
        soundtrack_input.update_columns(mureka_file_status: "failed")
        return
      end
      soundtrack_input.update!(mureka_file_status: "uploading")
    end

    extension = SoundtrackInput::EXTENSIONS.fetch(soundtrack_input.file.blob.content_type)
    Tempfile.create([ "soundtrack", extension ], binmode: true) do |tmp|
      bytes = 0
      soundtrack_input.file.download do |chunk|
        bytes += chunk.bytesize
        if bytes > SoundtrackInput::MAX_FILE_SIZE
          soundtrack_input.update_columns(mureka_file_status: "failed")
          return
        end
        tmp.write(chunk)
      end
      tmp.flush

      result = MusicGenerator::MurekaFilesUploadClient.call(
        file_path: tmp.path,
        purpose:   "soundtrack"
      )

      if result.success?
        soundtrack_input.update!(
          mureka_file_id:     result.value[:file_id],
          mureka_file_status: "ready"
        )
        GenerateSoundtrackJob.perform_later(order_id, soundtrack_input.id)
      else
        soundtrack_input.update!(mureka_file_status: "failed")
      end
    end
  rescue => e
    soundtrack_input&.update_columns(mureka_file_status: "failed") if soundtrack_input&.mureka_file_status == "uploading"
    Rails.logger.error "[UploadSoundtrackInputToMurekaJob] Error for Order##{order_id}: #{e.message}"
    raise
  end
end
