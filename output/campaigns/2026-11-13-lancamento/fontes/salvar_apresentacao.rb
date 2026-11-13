require "json"
ActiveJob::Base.queue_adapter = :test
root = Rails.root.join("output/campaigns/2026-11-13-lancamento")
state = JSON.parse(root.join("fontes/production_state.json").read)
campaign = Campaign.find(state.fetch("campaign_id"))
File.open(root.join("video/virajingle-apresentacao-27s.mp4")) do |file|
  campaign.video.attach(io: file, filename: "virajingle-apresentacao-27s.mp4", content_type: "video/mp4", metadata: {duration_seconds: 27.0, width: 1080, height: 1920, production_batch: "2026-11-13-lancamento", editorial_presentation: true})
end
File.open(root.join("video/cenas/01-abertura.png")) do |file|
  campaign.poster.attach(io: file, filename: "virajingle-apresentacao-capa.png", content_type: "image/png")
end
campaign.update!(video_status: "ready", video_error: nil)
GenerationCost.record!(order: campaign.order, operation: "video_render", provider: "local", model: "ffmpeg-editorial", usage: {production_batch: "2026-11-13-lancamento", duration_seconds: 27, width: 1080, height: 1920, bytes: campaign.video.blob.byte_size, outcome: "ready"})
state.merge!(final_video: "video/virajingle-apresentacao-27s.mp4", final_video_status: "ready", final_video_bytes: campaign.video.blob.byte_size, saved_at: Time.current.iso8601)
File.write(root.join("fontes/production_state.json"), JSON.pretty_generate(state))
puts({campaign_id:campaign.id, reference:campaign.order.reference, status:campaign.order.status, video_status:campaign.video_status, video_saved:campaign.video.blob.service.exist?(campaign.video.blob.key), audio_saved:campaign.selected_music_asset.campaign_audio.blob.service.exist?(campaign.selected_music_asset.campaign_audio.blob.key)}.to_json)
