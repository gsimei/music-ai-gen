# frozen_string_literal: true

class SongsController < ApplicationController
  def index
    @orders = policy_scope(Order)
                .left_joins(:campaign)
                .where("orders.status = ? OR (campaigns.id IS NOT NULL AND orders.status NOT IN (?))", "approved", %w[cancelled refunded])
                .includes(:briefing, :order_assets, campaign: { poster_attachment: :blob, photos_attachments: :blob, photo_attachment: :blob })
                .order(updated_at: :desc)
  end
end
