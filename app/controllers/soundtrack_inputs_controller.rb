# frozen_string_literal: true

class SoundtrackInputsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order

  def new
    @soundtrack_input = @order.soundtrack_input || SoundtrackInput.new(order: @order)
  end

  def create
    result = Orders::SoundtrackUpload.call(order: @order, file: params.dig(:soundtrack_input, :file))
    if result.success?
      render turbo_stream: turbo_stream.replace(
        "soundtrack-upload-section",
        partial: "orders/soundtrack_uploading",
        locals:  { order: @order }
      )
    else
      @soundtrack_input = @order.soundtrack_input || SoundtrackInput.new(order: @order)
      @soundtrack_input.errors.add(:file, :invalid)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_order
    @order = current_user.orders.find(params[:order_id])
    redirect_to root_path unless @order.soundtrack_upload_allowed?
  end
end
