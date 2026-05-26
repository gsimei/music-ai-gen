# frozen_string_literal: true

class LyricsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order
  before_action -> { authorize @order, :lyrics? }

  def show
    unless @order.lyrics_ready?
      redirect_to order_path(@order) and return
    end

    @draft = @order.lyrics_drafts.order(version: :desc).first
  end

  def approve
    result = Orders::LyricsApprover.call(order: @order, draft_id: params[:draft_id])

    if result.success?
      redirect_to order_path(@order), notice: t("lyrics.approved")
    else
      redirect_to order_lyrics_path(@order), alert: t("lyrics.approve_failed")
    end
  end

  def regenerate
    result = Orders::LyricsRegenerator.call(
      order:         @order,
      user_feedback: params.dig(:regenerate, :feedback) || params[:user_feedback]
    )

    respond_to do |format|
      format.turbo_stream do
        if result.success?
          render turbo_stream: turbo_stream.replace(
            "lyrics_generating_notice",
            partial: "lyrics/generating"
          )
        else
          render turbo_stream: turbo_stream.replace(
            "lyrics_errors",
            partial: "lyrics/error",
            locals: { message: result.errors }
          )
        end
      end
      format.html { redirect_to order_lyrics_path(@order) }
    end
  end

  private

  def set_order
    @order = Order.find(params[:id])
  end
end
