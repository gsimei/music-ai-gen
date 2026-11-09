namespace :campaigns do
  desc "Export campaign usage and estimated costs as CSV (optional CAMPAIGN_ID)"
  task costs: :environment do
    scope = ENV["CAMPAIGN_ID"].present? ? Campaign.where(id: ENV["CAMPAIGN_ID"]) : Campaign.all
    emit = ->(row) { puts row.map { |value| '"' + value.to_s.gsub('"', '""') + '"' }.join(",") }
    emit.call(%w[campaign_id order_reference price_brl completed_rounds cost_events estimated_api_brl uncertain_api_brl unpriced_api_events render_seconds video_bytes untracked_music_attempts first_cost_event audio_preview_seconds])
    scope.includes(:order).find_each do |campaign|
      order = campaign.order
      events = order.generation_costs
      api = events.where.not(provider: "local")
      renders = events.where(operation: "video_render").to_a
      emit.call([campaign.id, order.reference, order.price_cents / 100.0, order.completed_music_rounds, events.count,
        api.exists? ? api.sum(:estimated_brl).to_f.round(4) : nil, api.exists? ? api.where(status: "uncertain").sum(:estimated_brl).to_f.round(4) : nil,
        api.where(status: "unpriced").count, renders.sum { |event| event.usage["wall_seconds"].to_f }.round(3),
        campaign.video.attached? ? campaign.video.blob.byte_size : 0,
        order.music_generations.where.not(id: events.where.not(music_generation_id: nil).select(:music_generation_id)).count,
        events.minimum(:created_at)&.iso8601,
        events.where(operation: "audio_preview").sum { |event| event.usage["wall_seconds"].to_f }.round(3)])
    end
  end
end
