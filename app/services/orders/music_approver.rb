# frozen_string_literal: true

module Orders
  # Approves a music variant for an order that is in the preview_ready state.
  #
  # Validates:
  #   - variant is present and included in Order::APPROVED_VARIANTS
  #   - order is in preview_ready state
  #   - a matching OrderAsset (kind: music_variant) exists for the chosen variant
  #
  # On success:
  #   - Sets order.approved_variant to the chosen variant letter
  #   - Sets order.approved_music_generation_id from the matching OrderAsset
  #   - Fires the approve_music! AASM event (→ status: "approved")
  #
  # Returns ServiceResult with the updated order on success, errors on failure.
  class MusicApprover < BaseService
    attribute :order
    attribute :variant, :string
    attribute :asset_id
    attribute :preview_revision

    VARIANT_INDEX = { "a" => 0, "b" => 1 }.freeze

    def call
      return approve_campaign_asset if order.campaign
      validate_variant!
      validate_order_state!
      return failure_result(errors) if errors.any?

      asset = find_variant_asset
      if asset.nil?
        errors.add(:base, :not_found)
        return failure_result(errors)
      end

      order.approved_variant             = variant
      order.approved_music_generation_id = asset.music_generation_id
      order.approve_music!
      order.campaign&.queue_video!

      success_result(order)
    rescue AASM::InvalidTransition => e
      errors.add(:base, e.message)
      failure_result(errors)
    end

    private

    def approve_campaign_asset
      order.with_lock do
        return failure_result(:invalid_state) unless %w[preview_ready music_failed].include?(order.status) && order.lyrics_revision_token.blank?
        asset = if asset_id.present?
          order.all_music_assets.find_by(id: asset_id)
        else
          order.music_variant_assets.find_by(variant_index: VARIANT_INDEX[variant]) if VARIANT_INDEX.key?(variant)
        end
        return failure_result(:not_found) unless asset
        return failure_result(:preview_not_ready) unless asset.campaign_preview_ready?
        expected = preview_revision.nil? ? 0 : Integer(preview_revision.to_s, exception: false)
        return failure_result(:stale_preview) unless expected == asset.preview_revision
        order.update!(approved_variant: ("a".ord + asset.variant_index).chr,
          approved_music_generation_id: asset.music_generation_id,
          approved_lyrics_draft_id: asset.music_generation.lyrics_draft_id,
          favorite_music_asset_id: asset.id, approved_at: Time.current, status: "approved")
      end
      order.campaign.queue_video!
      success_result(order)
    end

    def validate_variant!
      if variant.blank?
        errors.add(:variant, :blank)
      elsif Order::APPROVED_VARIANTS.exclude?(variant)
        errors.add(:variant, :inclusion)
      end
    end

    def validate_order_state!
      return if errors[:variant].any?

      unless order.preview_ready?
        errors.add(:base, :invalid_state)
      end
    end

    def find_variant_asset
      index = VARIANT_INDEX[variant]
      order.music_variant_assets.find_by(variant_index: index)
    end
  end
end
