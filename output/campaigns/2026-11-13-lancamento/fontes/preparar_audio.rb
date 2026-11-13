require "json"
require "fileutils"
ActiveJob::Base.queue_adapter = :test
root = Rails.root.join("output/campaigns/2026-11-13-lancamento")
state = JSON.parse(root.join("fontes/production_state.json").read)
generation = MusicGeneration.find(state.fetch("generation_id"))
raise "A geração ainda não terminou" unless generation.completed?
generation.order_assets.order(:variant_index).each do |asset|
  ArchiveCampaignAudioJob.perform_now(asset.id) unless asset.audio.attached?
  PrepareCampaignAudioJob.perform_now(asset.id) unless asset.reload.audition_ready?
  asset.audio.blob.open do |source|
    FileUtils.cp(source.path, root.join("audio/virajingle-versao-#{asset.variant_index == 0 ? 'a' : 'b'}-completa.mp3"))
  end
end
asset = generation.order_assets.find_by!(variant_index: 1)
result = Campaigns::ExcerptSettings.call(order: generation.order, asset_id: asset.id, start_seconds: 19.6, duration_seconds: 27, revision: asset.preview_revision)
raise "Não foi possível preparar o trecho: #{result.errors}" unless result.success?
PrepareCampaignAudioJob.perform_now(asset.id, asset.reload.preview_revision)
asset.reload.campaign_audio.blob.open do |source|
  FileUtils.cp(source.path, root.join("audio/virajingle-jingle-27s.m4a"))
end
File.write(root.join("fontes/lyrics-sync.json"), JSON.pretty_generate(generation.order_assets.order(:variant_index).map { |a| {asset_id: a.id, variant: a.variant_index, duration_ms: a.duration_ms, lyrics_sync: a.lyrics_sync} }))
state.merge!(selected_asset_id: asset.id, selected_variant: "b", excerpt_start_seconds: 19.6, excerpt_duration_seconds: 27)
File.write(root.join("fontes/production_state.json"), JSON.pretty_generate(state))
puts({status: generation.order.reload.status, variants: generation.order_assets.count, selected_asset_id: asset.id, preview_revision: asset.preview_revision, excerpt: asset.campaign_audio.blob.metadata.slice("start_seconds", "duration_seconds", "track_duration_seconds")}.to_json)
