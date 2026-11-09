# frozen_string_literal: true

class MusicPreviewController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order

  def show
    authorize @order, :music_preview?

    return redirect_to order_chat_path(order_id: @order.id) if @order.campaign

    unless @order.preview_ready?
      redirect_to order_path(@order) and return
    end

    @assets = @order.music_variant_assets
  end

  def approve
    authorize @order, :approve_music?

    result = Orders::MusicApprover.call(order: @order, variant: params[:variant])

    if result.success?
      redirect_to order_path(@order), notice: t("music_preview.approved")
    else
      redirect_to order_music_preview_path(@order), alert: t("music_preview.approve_failed")
    end
  end

  private

  def set_order
    @order = Order.find(params[:id])
  end
end
