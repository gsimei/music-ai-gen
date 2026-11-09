# frozen_string_literal: true

class SoundtrackInputsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order

  def new
    @soundtrack_input = @order.build_soundtrack_input
  end

  def create
    file       = params.dig(:soundtrack_input, :file)
    input_type = detect_input_type(file)

    @soundtrack_input = @order.build_soundtrack_input(
      input_type:      input_type,
      storage_key:     file.original_filename,
      file_size_bytes: file.size,
      mime_type:       file.content_type
    )
    @soundtrack_input.file.attach(file)

    if @soundtrack_input.save
      UploadSoundtrackInputToMurekaJob.perform_later(@order.id)

      render turbo_stream: turbo_stream.replace(
        "soundtrack-upload-section",
        partial: "orders/soundtrack_uploading",
        locals:  { order: @order }
      )
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_order
    @order = current_user.orders.find(params[:order_id])
    redirect_to root_path unless @order.tier_config&.dig(:includes_soundtrack)
  end

  def detect_input_type(file)
    file.content_type.start_with?("image/") ? "image" : "video"
  end
end
