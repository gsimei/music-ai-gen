require "json"
require "fileutils"
ActiveJob::Base.queue_adapter = :test
root = Rails.root.join("output/campaigns/2026-11-13-lancamento")
state = JSON.parse(root.join("fontes/production_state.json").read)
campaign = Campaign.find(state.fetch("campaign_id"))
order = campaign.order
asset = OrderAsset.find(state.fetch("selected_asset_id"))
unless campaign.photos.attached?
  %w[loja-roupas loja-calcados salao-beleza].each do |name|
    File.open(root.join("assets/#{name}.png")) { |f| campaign.photos.attach(io: f, filename: "#{name}.png", content_type: "image/png") }
  end
end
unless campaign.logo.attached?
  File.open(Rails.root.join("public/brand/musical/virajingle-logo-white.png")) { |f| campaign.logo.attach(io: f, filename: "virajingle-logo-white.png", content_type: "image/png") }
end
unless order.approved?
  selection = Campaigns::MusicSelection.call(order: order, asset_id: asset.id)
  raise "Seleção indisponível: #{selection.errors}" unless selection.success?
  result = Orders::MusicApprover.call(order: order.reload, asset_id: asset.id, preview_revision: asset.reload.preview_revision, video_revision: campaign.reload.video_revision)
  raise "Aprovação indisponível: #{result.errors}" unless result.success?
end
RenderCampaignVideoJob.perform_now(campaign.id) unless campaign.reload.video_status == "ready"
campaign.reload
raise "Falha ao montar vídeo: #{campaign.video_error}" unless campaign.video_status == "ready" && campaign.video.attached?
campaign.video.blob.open { |f| FileUtils.cp(f.path, root.join("video/virajingle-video-sistema.mp4")) }
campaign.poster.blob.open { |f| FileUtils.cp(f.path, root.join("fontes/poster-sistema.png")) }
puts({campaign_id:campaign.id, reference:order.reference, order_status:order.reload.status, video_status:campaign.video_status, video_bytes:campaign.video.blob.byte_size, photos:campaign.product_photos.size}.to_json)
