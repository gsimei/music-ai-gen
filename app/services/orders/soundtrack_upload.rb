# frozen_string_literal: true

module Orders
  class SoundtrackUpload < BaseService
    attribute :order
    attribute :file

    def call
      return failure_result(:invalid_file) unless SoundtrackInput.acceptable_upload?(file)

      order.with_lock do
        return failure_result(:invalid_state) unless order.soundtrack_upload_allowed?
        previous = order.soundtrack_input
        return failure_result(:busy) if previous && !previous.failed?

        input = SoundtrackInput.new(order: order, input_type: file.content_type.split("/").first,
          storage_key: file.original_filename, file_size_bytes: file.size, mime_type: file.content_type)
        input.file.attach(file)
        return failure_result(:invalid_file) unless input.valid?

        previous&.destroy!
        input.save!
        order.reload
        UploadSoundtrackInputToMurekaJob.perform_later(order.id, input.id) if order.paid?
        success_result(input)
      end
    end
  end
end
