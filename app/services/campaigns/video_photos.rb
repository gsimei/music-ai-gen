module Campaigns
  class VideoPhotos < BaseService
    attribute :order
    attribute :revision
    attribute :photos
    attribute :photo_sequence

    def call
      order.with_lock do
        return failure_result(:invalid_state) unless order.campaign && %w[preview_ready music_failed].include?(order.status) && order.lyrics_revision_token.blank?
        campaign = order.campaign
        return failure_result(:stale_video) unless Integer(revision.to_s, exception: false) == campaign.video_revision
        return failure_result(:invalid_photos) unless photo_sequence.is_a?(Array) && (photos.nil? || photos.is_a?(Array))
        uploads = Array(photos).reject(&:blank?)
        sequence = photo_sequence.reject(&:blank?)
        limit = campaign.photo_limit
        return failure_result(:photo_limit_exceeded) if sequence.size > limit || uploads.size > limit
        return failure_result(:invalid_photos) if sequence.uniq != sequence
        return failure_result(:invalid_photos) unless uploads.all? { |file| file.is_a?(ActionDispatch::Http::UploadedFile) }

        saved = campaign.product_photos.index_by { |photo| "saved:#{photo.id}" }
        available = saved.transform_values(&:blob).merge(uploads.each_with_index.to_h { |file, index| [ "upload:#{index}", file ] })
        return failure_result(:invalid_photos) unless sequence.all? { |key| available.key?(key) }
        return failure_result(:invalid_photos) unless uploads.each_index.all? { |index| sequence.include?("upload:#{index}") }
        return success_result(campaign) if uploads.empty? && sequence == saved.keys

        selected = sequence.map { |key| available.fetch(key) }
        campaign.assign_attributes(photos: selected, photo: nil, photo_order: [], video_revision: campaign.video_revision + 1)
        return failure_result(:invalid_photos) unless campaign.save
        attachments = campaign.photos.index_by(&:blob_id)
        # Attachment IDs survive reordering, so save the chosen order explicitly.
        saved_blob_ids = selected.grep(ActiveStorage::Blob).map(&:id)
        uploaded = campaign.photos.reject { |attachment| saved_blob_ids.include?(attachment.blob_id) }.sort_by(&:id).each
        ids = selected.map { |item| item.is_a?(ActiveStorage::Blob) ? attachments.fetch(item.id).id : uploaded.next.id }
        campaign.update!(photo_order: ids)
        success_result(campaign)
      end
    end
  end
end
