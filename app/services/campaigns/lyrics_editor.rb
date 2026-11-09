module Campaigns
  class LyricsEditor < BaseService
    attribute :order
    attribute :content, :string
    attribute :draft_id

    def call
      order.with_lock do
        return failure_result(:invalid_state) unless order.campaign && order.lyrics_editable?
        parent = order.current_draft
        return failure_result(:stale_draft) unless parent && parent.id.to_s == draft_id.to_s
        return failure_result(:invalid_content) if content.blank? || content.length > 5000
        return success_result(parent) if parent.content == content.strip
        draft = order.lyrics_drafts.create!(content: content.strip, source: "user_edited",
          version: parent.version + 1, parent_draft: parent,
          structure: { "title" => parent.structure["title"], "lyrics" => content.strip })
        order.update!(lyrics_revision_error: nil)
        success_result(draft)
      end
    end
  end
end
