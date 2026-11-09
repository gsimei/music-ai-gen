# frozen_string_literal: true

class UploadSoundtrackInputToMurekaJob < ApplicationJob
  queue_as :ai

  def perform(order_id)
    order            = Order.find(order_id)
    soundtrack_input = order.soundtrack_input
    return unless soundtrack_input

    soundtrack_input.update!(mureka_file_status: "pending")

    file_bytes = soundtrack_input.file.download
    ext        = File.extname(soundtrack_input.storage_key).presence || ".bin"

    Tempfile.create([ "soundtrack", ext ], binmode: true) do |tmp|
      tmp.write(file_bytes)
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
        GenerateSoundtrackJob.perform_later(order_id)
      else
        soundtrack_input.update!(mureka_file_status: "failed")
        order.fail_music! rescue AASM::InvalidTransition
      end
    end
  rescue => e
    Rails.logger.error "[UploadSoundtrackInputToMurekaJob] Error for Order##{order_id}: #{e.message}"
    raise
  end
end
