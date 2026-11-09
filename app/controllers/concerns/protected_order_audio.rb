# Signed storage URLs are bearer credentials, not an ownership check. All
# OrderAsset audio must go through CampaignAudioController, even if an old
# signed redirect/proxy/disk URL has already escaped into a browser.
module ProtectedOrderAudio
  extend ActiveSupport::Concern

  included do
    prepend_before_action :reject_protected_order_audio
  end

  private

  def reject_protected_order_audio
    return unless request.get? || request.head?
    # Resolve only route captures. Unrelated query keys must not override the
    # resource that the storage controller will actually serve.
    path = request.path_parameters
    blob = if path[:signed_id].present? || path[:signed_blob_id].present?
      ActiveStorage::Blob.find_signed(path[:signed_id].presence || path[:signed_blob_id])
    elsif path[:encoded_key].present?
      token = ActiveStorage.verifier.verified(path[:encoded_key], purpose: :blob_key)
      ActiveStorage::Blob.find_by(key: token["key"], service_name: token["service_name"]) if token
    end
    return unless blob
    protected = blob.metadata["private_order_audio"] ||
      (blob.metadata["source_blob_id"] && blob.metadata["preview_version"]) ||
      blob.attachments.where(record_type: "OrderAsset", name: %w[audio campaign_audio audition_audio],
        record_id: OrderAsset.joins(order: :campaign).select(:id)).exists?
    if protected
      response.headers["Cache-Control"] = "private, no-store"
      head :not_found
    end
  end
end
