module Campaigns
  # A round is reserved under the order lock, before enqueueing any paid API work.
  # Only completed pairs count toward the customer's three rounds.
  class MusicRounds < BaseService
    LIMIT = 3
    MODEL = "mureka-9".freeze
    MAX_PAID_ATTEMPTS = 5
    MAX_REQUESTS = 12
    attribute :order
    attribute :feedback, :string
    attribute :asset_id
    attribute :retry_failed, :boolean, default: false

    def call
      generation = nil
      order.with_lock do
        return failure_result(:invalid_state) unless order.campaign && %w[lyrics_approved preview_ready music_failed].include?(order.status)
        return failure_result(:busy) if order.lyrics_revision_token.present? || order.music_generations.where(status: %w[pending processing]).exists?
        return failure_result(:regen_limit_reached) if order.completed_music_rounds >= LIMIT
        unresolved = order.music_generations.failed.where(error_code: %w[generation_delayed status_unavailable]).where.not(mureka_job_id: [ nil, "" ]).order(:iteration).last
        if unresolved
          if retry_failed
            unresolved.update!(status: "processing", poll_lease_until: nil, next_poll_at: Time.current)
            order.update!(status: "music_generating")
            PollCampaignMusicJob.perform_later(unresolved.id)
            return success_result(unresolved)
          end
          return failure_result(:unresolved_generation)
        end
        return failure_result(:technical_limit_reached) if order.generation_costs.where(operation: "music").where("estimated_usd > 0").count >= MAX_PAID_ATTEMPTS || order.music_generations.sum(:submission_attempts) >= MAX_REQUESTS
        return failure_result(:feedback_too_long) if feedback.to_s.length > 400
        parent_asset = if asset_id.present?
          order.all_music_assets.find_by(id: asset_id)
        else
          order.all_music_assets.last
        end
        return failure_result(:not_found) if asset_id.present? && parent_asset.nil?
        previous = order.music_generations.failed.order(:iteration).last if retry_failed
        self.feedback = previous.melody_hint if previous && feedback.blank?
        draft = order.current_draft
        return failure_result(:no_draft) unless draft
        model = MODEL
        return failure_result(:unknown_model) unless GenerationCost.song_price(model)
        settings_unchanged = previous && previous.request_payload["sound_settings"] == order.campaign.sound_settings && previous.melody_hint.to_s == feedback.to_s
        payload = settings_unchanged ? previous.request_payload.deep_dup : build_payload(draft, model, parent_asset)
        # Preserve the failed musical request, while honoring any lyrics the
        # merchant explicitly saved since that attempt.
        payload["lyrics"] = draft.content
        payload["model"] = model
        payload["n"] = 2
        # Mureka's documented duration field only supports V9.5, 120–300s.
        # The 30s campaign excerpt is prepared locally and auditioned before approval.
        payload.delete("duration")
        generation = order.music_generations.create!(provider: "mureka", model: model, status: "pending",
          generation_type: "song", lyrics_draft: draft, voice: order.briefing.voice,
          iteration: (order.music_generations.maximum(:iteration) || 0) + 1,
          parent_generation_id: previous&.parent_generation_id || parent_asset&.music_generation_id,
          music_style: order.briefing.music_style, melody_hint: feedback.presence,
          request_payload: payload)
        if order.campaign.selected_music_asset_id?
          order.campaign.update!(selected_music_asset: nil, video_revision: order.campaign.video_revision + 1)
        end
        order.update!(status: "music_generating")
        GenerateCampaignMusicJob.perform_later(generation.id)
      end
      success_result(generation)
    end

    private

    def build_payload(draft, model, asset)
      # This is a NEW interpretation, with textual context; no promise of audio remixing.
      settings = order.campaign.sound_settings
      source = asset&.music_generation&.request_payload
      direction = source["direction"].presence if source && source["sound_settings"] == settings
      direction ||= order.campaign.musical_direction
      instruction = feedback.present? ? "Requested change (take priority): #{feedback}." : ""
      prompt = "#{instruction} Brazilian Portuguese commercial jingle, 30 seconds, vocals immediately, no intro or solos. Musical direction: #{direction.to_s.first(400)}. Preserve the supplied lyrics and offer exactly."
      { "model" => model, "n" => 2, "lyrics" => draft.content, "prompt" => prompt.first(1024),
        "gender" => settings["vocal_gender"] == "auto" ? nil : settings["vocal_gender"], "sound_settings" => settings,
        "direction" => [ direction, feedback.presence ].compact.join("; ").last(600),
        "source_asset_id" => asset&.id }
    end
  end
end
