# frozen_string_literal: true

class DeleteSoundtrackInputJob < ApplicationJob
  queue_as :default

  def perform(soundtrack_input_id)
    input = SoundtrackInput.find_by(id: soundtrack_input_id)
    return unless input

    input.file.purge if input.file.attached?
    input.update!(
      deleted_at:    Time.current,
      storage_key:   "deleted",
      mureka_file_id: nil
    )
  end
end
