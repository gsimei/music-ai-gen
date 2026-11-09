class CampaignAudioController < ApplicationController
  include ActiveStorage::Streaming

  before_action :set_asset

  def preview
    return head :not_found unless @asset.audition_ready?
    deliver(@asset.audition_audio.blob, disposition: "inline")
  end

  def final
    return head :not_found unless @asset.approved_for_delivery? && @asset.audio.attached?
    deliver(@asset.audio.blob, disposition: "attachment")
  end

  private

  def set_asset
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    order = current_user.orders.find(params[:order_id])
    raise ActiveRecord::RecordNotFound unless order.campaign && %w[preview_ready music_generating music_failed approved].include?(order.status)
    @asset = order.all_music_assets.find(params[:asset_id])
  end

  def deliver(blob, disposition:)
    if request.headers["Range"].present?
      send_blob_byte_range_data(blob, request.headers["Range"], disposition: disposition)
    else
      response.headers["Accept-Ranges"] = "bytes"
      response.headers["Content-Length"] = blob.byte_size.to_s
      send_blob_stream(blob, disposition: disposition)
    end
  rescue ActiveStorage::FileNotFoundError
    head :not_found
  end
end
